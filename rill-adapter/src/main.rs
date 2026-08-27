use rill_ml::{
    OnlineRegressor,
    decision::{
        DecisionId, DecisionLedger, DecisionLedgerConfig, PendingDecision as LedgerPendingDecision,
    },
    drift::{DriftDetector, PageHinkley, PageHinkleyConfig, PageHinkleyPortableStateV1},
    models::{LinearRegression, LinearRegressionConfig},
    optim::{Optimizer, SgdConfig},
    persistence::Snapshot,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    cmp::Ordering,
    env,
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

const EXPECTED_RILL_VERSION: &str = "1.5.3";
const ADAPTER_PROTOCOL_VERSION: u32 = 1;
const STATE_SCHEMA_VERSION: u32 = 2;
const FEATURE_COUNT: usize = 8;
const MAX_INPUT_BYTES: u64 = 512 * 1024;
const MAX_STATE_BYTES: u64 = 512 * 1024;
const MAX_CANDIDATES: usize = 128;
const MAX_PENDING: usize = 64;
const MAX_COMPLETED: usize = 256;
const FEEDBACK_WINDOW_SECONDS: u64 = 15 * 60;
const COMPLETED_RETENTION_SECONDS: u64 = 24 * 60 * 60;
type Ledger = DecisionLedger<Vec<f64>, String>;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PersistedState {
    schema_version: u32,
    generation: u64,
    accepted_feedback: u64,
    model: Snapshot<LinearRegression>,
    drift: PageHinkleyPortableStateV1,
    ledger: Ledger,
}
struct State {
    generation: u64,
    accepted_feedback: u64,
    model: LinearRegression,
    drift: PageHinkley,
    ledger: Ledger,
}
#[derive(Debug, Deserialize)]
struct RankRequest {
    #[serde(rename = "schemaVersion")]
    schema_version: u32,
    #[serde(rename = "runId")]
    run_id: String,
    #[serde(rename = "createdAt")]
    created_at: u64,
    candidates: Vec<Value>,
}
#[derive(Debug, Deserialize)]
struct FeedbackRequest {
    #[serde(rename = "schemaVersion")]
    schema_version: u32,
    decision: Value,
    outcome: Value,
}

fn exact_rill_identity() -> Result<(), String> {
    if rill_ml::RILL_VERSION != EXPECTED_RILL_VERSION {
        Err(format!(
            "adapter was built with rill-ml {}, expected {}",
            rill_ml::RILL_VERSION,
            EXPECTED_RILL_VERSION
        ))
    } else {
        Ok(())
    }
}
fn drift_config() -> PageHinkleyConfig {
    let mut c = PageHinkleyConfig::default();
    c.threshold = 2.0;
    c.warning_threshold = 1.0;
    c.alpha = 0.995;
    c.delta = 0.01;
    c.min_samples = 20;
    c
}
fn fresh_model() -> Result<LinearRegression, String> {
    let mut s = SgdConfig::default();
    s.learning_rate = 0.025;
    s.l2 = 0.0001;
    let o = Optimizer::sgd(FEATURE_COUNT, s).map_err(|e| e.to_string())?;
    let mut c = LinearRegressionConfig::default();
    c.optimizer = o;
    LinearRegression::new(FEATURE_COUNT, c).map_err(|e| e.to_string())
}
fn fresh_ledger() -> Result<Ledger, String> {
    let c = DecisionLedgerConfig::new(MAX_PENDING, MAX_COMPLETED)
        .map_err(|e| e.to_string())?
        .with_value_limits(FEATURE_COUNT * std::mem::size_of::<f64>(), 64)
        .map_err(|e| e.to_string())?;
    DecisionLedger::new(c).map_err(|e| e.to_string())
}
fn fresh_state() -> Result<State, String> {
    Ok(State {
        generation: 1,
        accepted_feedback: 0,
        model: fresh_model()?,
        drift: PageHinkley::new(drift_config()).map_err(|e| e.to_string())?,
        ledger: fresh_ledger()?,
    })
}

fn load_state(path: &Path) -> Result<State, String> {
    if !path.exists() {
        return fresh_state();
    }
    let meta = fs::metadata(path).map_err(|e| format!("state metadata: {e}"))?;
    if meta.len() > MAX_STATE_BYTES {
        return Err(format!("state exceeds {} bytes", MAX_STATE_BYTES));
    }
    let bytes = fs::read(path).map_err(|e| format!("state read: {e}"))?;
    let p: PersistedState =
        serde_json::from_slice(&bytes).map_err(|e| format!("state decode: {e}"))?;
    if p.schema_version != STATE_SCHEMA_VERSION {
        return Err(format!("unsupported state schema {}", p.schema_version));
    }
    p.ledger
        .validate()
        .map_err(|e| format!("ledger state validation: {e}"))?;
    let model = p
        .model
        .into_validated_model()
        .map_err(|e| format!("model state validation: {e}"))?;
    let drift = PageHinkley::restore_state_v1(drift_config(), p.drift)
        .map_err(|e| format!("drift state validation: {e}"))?;
    Ok(State {
        generation: p.generation,
        accepted_feedback: p.accepted_feedback,
        model,
        drift,
        ledger: p.ledger,
    })
}
fn save_state(path: &Path, state: &State) -> Result<(), String> {
    state
        .ledger
        .validate()
        .map_err(|e| format!("prospective ledger validation: {e}"))?;
    let p = PersistedState {
        schema_version: STATE_SCHEMA_VERSION,
        generation: state.generation,
        accepted_feedback: state.accepted_feedback,
        model: Snapshot::new(state.model.clone()),
        drift: state.drift.export_state_v1(),
        ledger: state.ledger.clone(),
    };
    let bytes = serde_json::to_vec_pretty(&p).map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_STATE_BYTES {
        return Err("prospective state exceeds byte bound".into());
    }
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent).map_err(|e| format!("state mkdir: {e}"))?;
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut f = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&tmp)
        .map_err(|e| format!("state temp create: {e}"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600))
            .map_err(|e| format!("state chmod: {e}"))?;
    }
    f.write_all(&bytes)
        .map_err(|e| format!("state write: {e}"))?;
    f.sync_all().map_err(|e| format!("state fsync: {e}"))?;
    drop(f);
    fs::rename(&tmp, path).map_err(|e| format!("state atomic rename: {e}"))?;
    #[cfg(unix)]
    if let Ok(d) = fs::File::open(parent) {
        let _ = d.sync_all();
    }
    Ok(())
}
fn read_json_file(path: &Path) -> Result<Value, String> {
    let m = fs::metadata(path).map_err(|e| format!("input metadata: {e}"))?;
    if m.len() > MAX_INPUT_BYTES {
        return Err(format!("input exceeds {} bytes", MAX_INPUT_BYTES));
    }
    serde_json::from_slice(&fs::read(path).map_err(|e| format!("input read: {e}"))?)
        .map_err(|e| format!("input decode: {e}"))
}
fn finite_num(v: &Value, p: &str, d: f64) -> Result<f64, String> {
    match v.pointer(p).and_then(Value::as_f64) {
        Some(n) if n.is_finite() => Ok(n),
        Some(_) => Err(format!("non-finite feature at {p}")),
        None => Ok(d),
    }
}
fn candidate_features(c: &Value) -> Result<Vec<f64>, String> {
    Ok(vec![
        finite_num(c, "/avgLatencyMs", 0.0)?.clamp(0.0, 10000.0) / 1000.0,
        finite_num(c, "/downloadMBps", 0.0)?.clamp(0.0, 10000.0) / 100.0,
        finite_num(c, "/lossRate", 1.0)?.clamp(0.0, 1.0),
        finite_num(c, "/probeSummary/connectMs", 10000.0)?.clamp(0.0, 10000.0) / 1000.0,
        finite_num(c, "/probeSummary/tlsMs", 10000.0)?.clamp(0.0, 10000.0) / 1000.0,
        finite_num(c, "/probeSummary/ttfbMs", 10000.0)?.clamp(0.0, 10000.0) / 1000.0,
        finite_num(c, "/probeSummary/totalMs", 10000.0)?.clamp(0.0, 10000.0) / 1000.0,
        finite_num(c, "/nativeRank", 128.0)?.clamp(1.0, 128.0) / 128.0,
    ])
}
fn candidate_ip(c: &Value) -> Result<String, String> {
    c.get("ip")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty() && s.len() <= 64)
        .map(ToOwned::to_owned)
        .ok_or_else(|| "candidate missing bounded ip".into())
}
fn decision_id(run_id: &str) -> DecisionId {
    let d = Sha256::digest(run_id.as_bytes());
    let mut b = [0u8; 16];
    b.copy_from_slice(&d[..16]);
    DecisionId(u128::from_be_bytes(b))
}
fn json_error(m: impl Into<String>) -> Value {
    json!({"success":false,"error":m.into()})
}

fn command_status(path: &Path) -> Value {
    match exact_rill_identity().and_then(|_| load_state(path)) {
        Ok(s) => {
            json!({"success":true,"adapterProtocolVersion":ADAPTER_PROTOCOL_VERSION,"rillVersion":rill_ml::RILL_VERSION,"stateSchemaVersion":STATE_SCHEMA_VERSION,"generation":s.generation,"samplesSeen":s.model.samples_seen(),"acceptedFeedback":s.accepted_feedback,"pendingDecisions":s.ledger.pending_len(),"completedDecisions":s.ledger.completed_len(),"drift":format!("{:?}",s.drift.level()).to_lowercase(),"stateBytes":fs::metadata(path).map(|m|m.len()).unwrap_or(0),"resourceBounds":{"maxCandidates":MAX_CANDIDATES,"maxPending":MAX_PENDING,"maxCompleted":MAX_COMPLETED,"maxStateBytes":MAX_STATE_BYTES,"feedbackWindowSeconds":FEEDBACK_WINDOW_SECONDS}})
        }
        Err(e) => json_error(e),
    }
}

fn command_rank(path: &Path, input: &Path) -> Result<Value, String> {
    exact_rill_identity()?;
    let raw = read_json_file(input)?;
    let req: RankRequest = serde_json::from_value(raw).map_err(|e| e.to_string())?;
    if req.schema_version != 1
        || req.run_id.is_empty()
        || req.run_id.len() > 128
        || req.created_at == 0
    {
        return Err("invalid rank request envelope".into());
    }
    if req.candidates.is_empty() || req.candidates.len() > MAX_CANDIDATES {
        return Err("candidate count outside resource bounds".into());
    }
    let mut s = load_state(path)?;
    s.ledger.clear_expired(req.created_at);
    s.ledger
        .clear_completed_before(req.created_at.saturating_sub(COMPLETED_RETENTION_SECONDS));
    let mut scored = Vec::with_capacity(req.candidates.len());
    for c in req.candidates {
        let ip = candidate_ip(&c)?;
        let f = candidate_features(&c)?;
        let score = s.model.predict(&f).map_err(|e| e.to_string())?;
        if !score.is_finite() {
            return Err("model produced non-finite score".into());
        }
        let nr = c
            .get("nativeRank")
            .and_then(Value::as_u64)
            .unwrap_or(u64::MAX);
        scored.push((c, ip, f, score, nr));
    }
    scored.sort_by(|a, b| {
        b.3.partial_cmp(&a.3)
            .unwrap_or(Ordering::Equal)
            .then_with(|| a.4.cmp(&b.4))
            .then_with(|| a.1.cmp(&b.1))
    });
    let actual = scored
        .iter()
        .min_by_key(|x| x.4)
        .ok_or_else(|| "no actual candidate".to_string())?;
    let id = decision_id(&req.run_id);
    s.ledger
        .register(LedgerPendingDecision::new(
            id,
            actual.2.clone(),
            actual.1.clone(),
            req.created_at,
            req.created_at.saturating_add(FEEDBACK_WINDOW_SECONDS),
            s.generation,
        ))
        .map_err(|e| format!("decision registration: {e}"))?;
    save_state(path, &s)?;
    let candidates = scored
        .into_iter()
        .enumerate()
        .map(|(i, (mut c, _, _, score, _))| {
            if let Some(o) = c.as_object_mut() {
                o.insert("rillRank".into(), json!(i + 1));
                o.insert("rillScore".into(), json!(score));
            }
            c
        })
        .collect::<Vec<_>>();
    let samples = s.model.samples_seen();
    Ok(
        json!({"success":true,"adapterProtocolVersion":ADAPTER_PROTOCOL_VERSION,"rillVersion":rill_ml::RILL_VERSION,"generation":s.generation,"decisionId":format!("{:032x}",id.0),"samplesSeen":samples,"confidence":((samples as f64)/50.0).clamp(0.0,1.0),"drift":format!("{:?}",s.drift.level()).to_lowercase(),"candidates":candidates}),
    )
}

fn command_feedback(path: &Path, input: &Path) -> Result<Value, String> {
    exact_rill_identity()?;
    let req: FeedbackRequest =
        serde_json::from_value(read_json_file(input)?).map_err(|e| e.to_string())?;
    if req.schema_version != 1
        || req.outcome.get("validated").and_then(Value::as_bool) != Some(true)
    {
        return Err("feedback must be schema v1 and validated".into());
    }
    let run = req
        .decision
        .get("runId")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty() && s.len() <= 128)
        .ok_or_else(|| "decision missing bounded runId".to_string())?;
    let ip = req
        .outcome
        .get("ip")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty() && s.len() <= 64)
        .ok_or_else(|| "outcome missing bounded ip".to_string())?
        .to_owned();
    let reward = req
        .outcome
        .get("reward")
        .and_then(Value::as_f64)
        .filter(|v| v.is_finite())
        .ok_or_else(|| "outcome reward is missing/non-finite".to_string())?;
    let observed = req
        .outcome
        .get("observedAt")
        .and_then(Value::as_u64)
        .filter(|v| *v > 0)
        .ok_or_else(|| "outcome missing observedAt".to_string())?;
    let generation = req
        .decision
        .get("generation")
        .and_then(Value::as_u64)
        .ok_or_else(|| "decision missing generation".to_string())?;
    let id = decision_id(run);
    let mut s = load_state(path)?;
    s.ledger
        .clear_completed_before(observed.saturating_sub(COMPLETED_RETENTION_SECONDS));
    let pending = s
        .ledger
        .pending(id)
        .ok_or_else(|| "unknown/stale decision".to_string())?;
    let ctx = pending.context.clone();
    if pending.model_generation != generation {
        return Err("model generation mismatch".into());
    }
    if pending.action != ip {
        return Err("action/ip mismatch".into());
    }
    let pred = s.model.predict(&ctx).map_err(|e| e.to_string())?;
    let mut model = s.model.clone();
    model.learn(&ctx, reward).map_err(|e| e.to_string())?;
    let mut drift = s.drift.clone();
    drift
        .update((pred - reward).abs())
        .map_err(|e| e.to_string())?;
    let mut ledger = s.ledger.clone();
    ledger
        .apply_feedback(rill_ml::decision::DecisionOutcome {
            decision_id: id,
            action: ip,
            reward,
            observed_at: observed,
            model_generation: generation,
        })
        .map_err(|e| format!("decision feedback: {e}"))?;
    s.model = model;
    s.drift = drift;
    s.ledger = ledger;
    s.accepted_feedback = s.accepted_feedback.saturating_add(1);
    s.generation = s.generation.saturating_add(1);
    save_state(path, &s)?;
    Ok(
        json!({"success":true,"accepted":true,"generation":s.generation,"samplesSeen":s.model.samples_seen(),"drift":format!("{:?}",s.drift.level()).to_lowercase()}),
    )
}

fn parse_args() -> Result<(String, PathBuf, Option<PathBuf>), String> {
    let mut it = env::args().skip(1);
    let cmd = it.next().ok_or_else(|| "missing command".to_string())?;
    let mut state = None;
    let mut input = None;
    while let Some(a) = it.next() {
        match a.as_str() {
            "--state" => state = it.next().map(PathBuf::from),
            "--input" => input = it.next().map(PathBuf::from),
            _ => return Err(format!("unexpected argument: {a}")),
        }
    }
    Ok((
        cmd,
        state.ok_or_else(|| "--state is required".to_string())?,
        input,
    ))
}
fn main() {
    let result = (|| -> Result<Value, String> {
        let (cmd, state, input) = parse_args()?;
        match cmd.as_str() {
            "status" => Ok(command_status(&state)),
            "rank" => command_rank(&state, input.as_deref().ok_or("--input is required")?),
            "feedback" => command_feedback(&state, input.as_deref().ok_or("--input is required")?),
            "reset" => {
                exact_rill_identity()?;
                if state.exists() {
                    fs::remove_file(&state).map_err(|e| e.to_string())?;
                }
                Ok(json!({"success":true,"reset":true,"rillVersion":rill_ml::RILL_VERSION}))
            }
            _ => Err("unknown command".into()),
        }
    })();
    let (v, code) = match result {
        Ok(v) => (v, 0),
        Err(e) => (json_error(e), 1),
    };
    let mut out = io::stdout().lock();
    let _ = serde_json::to_writer(&mut out, &v);
    let _ = writeln!(&mut out);
    if code != 0 {
        std::process::exit(code);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feature_projection_is_bounded_and_deterministic() {
        let candidate = json!({
            "ip": "104.16.1.1",
            "avgLatencyMs": 50000.0,
            "downloadMBps": -1.0,
            "lossRate": 2.0,
            "probeSummary": {"connectMs": 20.0}
        });
        let features = candidate_features(&candidate).expect("valid feature input");
        assert_eq!(features.len(), FEATURE_COUNT);
        assert_eq!(features[0], 10.0);
        assert_eq!(features[1], 0.0);
        assert_eq!(features[2], 1.0);
        assert!(features.iter().all(|value| value.is_finite()));
    }

    #[test]
    fn candidate_identity_requires_bounded_nonempty_ip() {
        assert_eq!(candidate_ip(&json!({"ip":"1.2.3.4"})).unwrap(), "1.2.3.4");
        assert!(candidate_ip(&json!({"ip":""})).is_err());
        assert!(candidate_ip(&json!({"ip": "x".repeat(65)})).is_err());
    }

    #[test]
    fn decision_id_is_stable_for_a_run() {
        assert_eq!(decision_id("run-a"), decision_id("run-a"));
        assert_ne!(decision_id("run-a"), decision_id("run-b"));
    }
}
