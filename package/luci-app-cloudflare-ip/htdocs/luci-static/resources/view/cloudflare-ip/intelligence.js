'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require cloudflare-ip/utils as utils';

var callStatus = rpc.declare({ object: 'cf_ip', method: 'status', expect: { '': {} } });
var callSelfCheck = rpc.declare({ object: 'cf_ip', method: 'rill-self-check', expect: { '': {} } });
var callDiagnostics = rpc.declare({ object: 'cf_ip', method: 'rill-diagnostics', expect: { '': {} } });
var callAdaptiveStatus = rpc.declare({ object: 'cf_ip', method: 'adaptive-status', expect: { '': {} } });
var callReset = rpc.declare({ object: 'cf_ip', method: 'rill-reset', params: [ 'expectedGeneration' ], expect: { '': {} } });

function runtimeSummary(status) {
	status = status || {};
	if (status._statusError)
		return _('Status unavailable / Native fallback');
	var intelligence = status.intelligence || {};
	var requestedMode = status.requestedMode || intelligence.requestedMode || intelligence.mode || 'off';
	var effectiveMode = status.effectiveMode || intelligence.effectiveMode || requestedMode;
	var fallbackReason = status.fallbackReason || intelligence.fallbackReason || '';

	if (requestedMode === 'assisted' && effectiveMode === 'shadow')
		return _('Assisted requested → Shadow fallback') + ' / ' + (fallbackReason || _('consumer not qualified'));

	if (intelligence.available === true)
		return _('Available') + ' / ' + (intelligence.runtimeVersion || _('version unknown'));

	if (intelligence.state === 'disabled' || requestedMode === 'off')
		return _('Disabled / Native ranking');

	return _('Unavailable / Native fallback') + (intelligence.state ? ' / ' + intelligence.state : '');
}

return view.extend({
	title: _('Rill Intelligence'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			callStatus().catch(function() { return { _statusError: true }; }),
			callDiagnostics().catch(function() { return {}; }),
			callAdaptiveStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		utils.loadSharedCSS();
		data = data || [];
		var status = data[1] || {};
		var diagnostics = data[2] || {};
		var adaptiveResponse = data[3] || {};
		var adaptive = adaptiveResponse.adaptiveMeasurement || status.adaptiveMeasurement || {};
		var adaptiveAggregate = adaptive.aggregate || {};
		function adaptiveNumber(value, digits) {
			return value == null || !isFinite(Number(value)) ? _('unavailable') : Number(value).toFixed(digits || 2);
		}
		var m = new form.Map('cf_ip', _('Rill Intelligence'),
			_('The generic Rill Runtime is supplied by OpenWrt packaging. Cloudflare IP owns candidate validation, ranking policy, reward and proxy transactions.'));
		var s, o;

		s = m.section(form.TypedSection, 'main', _('Measurement Policy'));
		s.anonymous = true;
		o = s.option(form.ListValue, 'source_policy', _('Source Strategy'));
		o.value('balanced', _('Balanced'));
		o.value('official-heavy', _('Official-heavy'));
		o.value('history-heavy', _('History-heavy'));
		o.value('diversity-heavy', _('Diversity-heavy'));
		o.value('community-heavy', _('Community-heavy'));
		o.default = 'balanced';
		o = s.option(form.Value, 'probe_batch_size', _('Probe Batch Size'));
		o.datatype = 'range(1,16)';
		o.default = '4';
		o = s.option(form.Value, 'max_probe_count', _('Maximum Probes'));
		o.datatype = 'range(1,32)';
		o.default = '8';
		o = s.option(form.Flag, 'early_stop_enabled', _('Deterministic Early Stop'));
		o.default = '1';

		s = m.section(form.TypedSection, 'main', _('Adaptive Measurement'));
		s.anonymous = true;
		o = s.option(form.Flag, 'adaptive_measurement_enabled', _('Enable Adaptive Measurement'));
		o.default = '1';
		o = s.option(form.ListValue, 'adaptive_measurement_mode', _('Mode'));
		o.value('off', _('Off'));
		o.value('shadow', _('Shadow'));
		o.value('guarded', _('Guarded (qualified only)'));
		o.default = 'shadow';
		o.description = _('Shadow records counterfactual evidence without changing production probe order. Guarded is enabled only after fresh, complete, real audit evidence.');
		o = s.option(form.DummyValue, '_adaptive_state', _('Current State'));
		o.cfgvalue = function() { return (adaptive.qualificationState || _('insufficient')) + ' / ' + (adaptive.effectiveMode || _('shadow')); };
		o = s.option(form.DummyValue, '_adaptive_modes', _('Requested / Effective Mode'));
		o.cfgvalue = function() { return (adaptive.requestedMode || _('unavailable')) + ' / ' + (adaptive.effectiveMode || _('unavailable')); };
		o = s.option(form.DummyValue, '_adaptive_evidence', _('Audit Evidence'));
		o.cfgvalue = function() { return (adaptive.evidenceCount || 0) + ' / ' + _('fresh at') + ': ' + (adaptive.freshAt || _('never')); };
		o = s.option(form.DummyValue, '_adaptive_recall', _('Winner / Top-N Recall'));
		o.cfgvalue = function() { return adaptiveNumber(adaptiveAggregate.winnerRecall, 3) + ' / ' + adaptiveNumber(adaptiveAggregate.topNRecall, 3); };
		o = s.option(form.DummyValue, '_adaptive_eligibility', _('Eligible Insufficiency Rate'));
		o.cfgvalue = function() { return adaptiveNumber(adaptiveAggregate.eligibleInsufficiencyRate, 3); };
        o = s.option(form.DummyValue, '_adaptive_savings', _('Replay Probe Savings'));
        o.cfgvalue = function() { return adaptiveAggregate.estimatedProbeSavings == null ? _('unavailable') : adaptiveNumber(adaptiveAggregate.estimatedProbeSavings * 100, 1) + '% / replay'; };
		o = s.option(form.DummyValue, '_adaptive_audit', _('Full Audit'));
		o.cfgvalue = function() { var last = adaptive.lastFullAudit || {}; return (last.at || _('never')) + ' / ' + _('next in runs') + ': ' + (adaptive.nextAuditInRuns == null ? _('unavailable') : adaptive.nextAuditInRuns); };
		o = s.option(form.DummyValue, '_adaptive_scheduler', _('Scheduler Contract'));
		o.cfgvalue = function() { return 'v' + (adaptive.schedulerVersion || '?') + ' / ' + _('feature contract') + ' v' + (adaptive.featureContractVersion || '?'); };
		o = s.option(form.DummyValue, '_adaptive_selection', _('Selection'));
		o.cfgvalue = function() { return _('K') + ': ' + (adaptive.selectedK || 0) + ', ' + _('expansions') + ': ' + (adaptive.lastExpansionCount || 0) + ', ' + _('last fallback') + ': ' + (adaptive.lastFallbackReason || _('none')); };

		s = m.section(form.TypedSection, 'main', _('Product Intelligence Summary'));
		s.anonymous = true;
		o = s.option(form.DummyValue, '_endpoint', _('Current Endpoint'));
		o.cfgvalue = function() { return (status.best_ips || []).join(', ') || _('Unavailable'); };
		o = s.option(form.DummyValue, '_health_summary', _('System Health'));
		o.cfgvalue = function() { var h = status.operationalHealth || {}; return h.state || _('healthy'); };
		o = s.option(form.DummyValue, '_adaptive_summary', _('Adaptive Measurement'));
		o.cfgvalue = function() { return (adaptive.requestedMode || _('off')) + ' → ' + (adaptive.effectiveMode || _('off')) + ' / ' + (adaptive.qualificationState || _('insufficient')); };
		o = s.option(form.DummyValue, '_candidate_summary', _('Candidate Intelligence'));
		o.cfgvalue = function() { var d = status.decision || {}; return (d.effectiveMode === 'assisted' ? _('Candidate Assisted') : (d.effectiveMode === 'shadow' ? _('Candidate Shadow') : _('Native only'))) + ' / ' + (d.confidenceLevel || _('unavailable')); };
		o = s.option(form.DummyValue, '_next_audit_summary', _('Next Full Audit / Optimize'));
		o.cfgvalue = function() { return (adaptive.nextAuditInRuns == null ? _('unavailable') : adaptive.nextAuditInRuns + ' ' + _('runs')) + ' / ' + ((status.reusePolicy || {}).reason || _('policy current')); };

		s = m.section(form.TypedSection, 'main', _('Operational Health'));
		s.anonymous = true;
		o = s.option(form.DummyValue, '_health_state', _('State'));
		o.cfgvalue = function() { var h = status.operationalHealth || {}; return h.state || _('healthy'); };
		o = s.option(form.DummyValue, '_health_reasons', _('Reason Codes'));
		o.cfgvalue = function() { var h = status.operationalHealth || {}; return (h.reasonCodes || []).join(', ') || _('none'); };
		o = s.option(form.DummyValue, '_why_run', _('Why This Run'));
		o.cfgvalue = function() { return status.whyThisRun || _('Native measurement'); };
		o = s.option(form.DummyValue, '_context_policy', _('Current Context Policy'));
		o.cfgvalue = function() { var p = adaptive.contextPolicy || {}; return (p.policyId || _('conservative-default')) + (p.supported ? '' : ' / ' + _('conservative default')); };
		o = s.option(form.DummyValue, '_run_history', _('Recent Runs'));
		o.cfgvalue = function() {
			var rows = diagnostics.recentDecisions || [];
            function value(value) { return value == null || value === '' ? '—' : String(value); }
            return rows.slice(-20).map(function(row) {
                return [value(row.time || row.at), value(row.result), value((row.bestIps || []).join(',') || row.finalIp), value(row.adaptiveMode), value(row.candidateMode), value(row.actualUniqueProbeCount), value(row.fallbackUsed), value(row.measurementDurationMs) + ' ms'].join(' / ');
            }).join(' | ') || _('No history');
		};

		s = m.section(form.TypedSection, 'rill', _('Rill Runtime Consumer'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable Rill Intelligence'),
			_('Enable the optional Rill consumer. Native ranking remains authoritative when Rill is disabled or unavailable.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.ListValue, 'mode', _('Mode'));
		o.value('off', _('Off'));
		o.value('shadow', _('Shadow'));
		o.value('assisted', _('Assisted (qualification-gated)'));
		o.description = _('Assisted is qualification-gated and uses only the Native safe envelope; any Runtime problem falls back to Native.');
		o.default = 'shadow';

		o = s.option(form.Value, 'timeout_ms', _('Runtime Timeout (ms)'));
		o.datatype = 'range(100,10000)';
		o.default = '2000';

		o = s.option(form.Value, 'runtime', _('Runtime Path'));
		o.default = '/usr/bin/rill-runtime';

		o = s.option(form.Value, 'state_file', _('State File'));
		o.default = '/etc/cf_ip/rill-state.json';

		s = m.section(form.TypedSection, 'rill', _('Live State'));
		s.anonymous = true;
	o = s.option(form.DummyValue, '_state', _('Runtime'));
	o.cfgvalue = function() { return runtimeSummary(status); };
	o = s.option(form.DummyValue, '_channel', _('Runtime Channel'));
	o.cfgvalue = function() { return (status.intelligence || {}).channel || _('Unknown'); };
	o = s.option(form.DummyValue, '_api', _('Runtime API'));
	o.cfgvalue = function() { return (status.intelligence || {}).runtimeApiVersion || _('Unknown'); };
	o = s.option(form.DummyValue, '_schema', _('Feature Schema'));
	o.cfgvalue = function() {
		var i = status.intelligence || {};
		return (i.featureSchemaVersion || '?') + (i.featureSchemaHash ? ' / ' + i.featureSchemaHash : '');
	};
	o = s.option(form.DummyValue, '_generation', _('State / Model Generation'));
	o.cfgvalue = function() {
		var i = status.intelligence || {};
		return (i.stateGeneration || 0) + ' / ' + (i.modelGeneration || 0);
	};
	o = s.option(form.DummyValue, '_learning', _('Learning'));
		o.cfgvalue = function() {
			var i = status.intelligence || {};
			return _('Valid feedback') + ': ' + (i.validFeedback || 0) + ', ' + _('delayed pending') + ': ' + (i.pendingDelayedFeedback || 0) + ', ' + _('completed') + ': ' + (i.delayedCompleted || 0) + ', Δ ' + (i.rewardDelta == null ? '?' : i.rewardDelta.toFixed(3));
		};
	o = s.option(form.DummyValue, '_health', _('Runtime Health'));
	o.cfgvalue = function() { var i = status.intelligence || {}; return (i.health || _('Unknown')) + (i.resourcePressure ? ' / ' + _('Resource pressure') : ''); };
	o = s.option(form.DummyValue, '_resource', _('Resource Guard'));
	o.cfgvalue = function() {
		var i = status.intelligence || {}, x = i.inspect || {}, u = x.resourceUtilization || {}, p = x.resourceProfile || {};
		return _('pressure') + ': ' + (i.resourcePressure ? _('yes') : _('no')) + ', ' + _('state bytes') + ': ' + (u.stateBytes || 0) + ' / ' + (p.maxModelStateBytes || '?') + ', ' + _('pending') + ': ' + (u.pendingDecisions || 0) + ' / ' + (p.maxPendingDecisions || '?');
	};
		o = s.option(form.DummyValue, '_inspect', _('Runtime Inspect'));
		o.cfgvalue = function() { var i = status.intelligence || {}, x = i.inspect || {}; return _('pending') + ': ' + (x.pendingDecisions || i.pendingDelayedFeedback || 0) + ', ' + _('completed') + ': ' + (x.completedDecisions || i.delayedCompleted || 0) + ', ' + _('last error') + ': ' + (x.lastError || _('None')); };
	o = s.option(form.DummyValue, '_authority', _('Current Authority'));
	o.cfgvalue = function() {
		return status.effectiveMode === 'assisted' ? _('Guarded Assisted') : (status.effectiveMode === 'shadow' ? _('Shadow') : _('Native'));
	};
	o = s.option(form.DummyValue, '_qualification', _('Qualification'));
	o.cfgvalue = function() { return (status.intelligence || {}).qualificationState || _('Unknown'); };
	o = s.option(form.DummyValue, '_context', _('Learning Context'));
	o.cfgvalue = function() {
		var c = status.learningContext || (status.intelligence || {}).learningContext || {};
		var changedAt = status.contextChangedAt || (status.intelligence || {}).contextChangedAt || null;
		return (c.contextFingerprint || _('Unknown')) + (status.contextChanged ? ' / ' + _('changed') : '') + (changedAt ? ' / ' + _('last changed') + ': ' + changedAt : '');
	};
	o = s.option(form.DummyValue, '_confidence', _('Decision Confidence'));
	o.cfgvalue = function() {
		var d = status.decision || {}, i = status.intelligence || {};
		return d.confidenceLevel || i.confidenceLevel || _('Unavailable / Native fallback');
	};
	o = s.option(form.DummyValue, '_confidence_reasons', _('Confidence Reasons'));
	o.cfgvalue = function() {
		var d = status.decision || {}, reasons = d.confidenceReasons || status.confidenceReasons || [];
		return reasons.length ? reasons.join(', ') : _('Unavailable / Native fallback');
	};
	o = s.option(form.DummyValue, '_selection', _('Decision Selection'));
	o.cfgvalue = function() {
		var d = status.decision || {}, native = (d.nativeOrder || [])[0] || '?', rill = (d.rillOrder || [])[0] || '?', final = d.authorityActionId || d.selectedActionId || '?';
		return _('Native top1') + ': ' + native + ', ' + _('Rill top1') + ': ' + rill + ', ' + _('final') + ': ' + final + ', ' + _('agreement') + ': ' + (d.nativeRillTop1Agreement ? _('yes') : _('no'));
	};
	o = s.option(form.DummyValue, '_evidence', _('Decision Evidence'));
	o.cfgvalue = function() {
		var e = status.evidenceAggregate || (status.intelligence || {}).evidenceAggregate || {};
		return _('comparable') + ': ' + (e.comparableDecisions || 0) + ', ' + _('wins') + ': ' + (e.wins || 0) + ', ' + _('ties') + ': ' + (e.ties || 0) + ', ' + _('losses') + ': ' + (e.losses || 0) + ', Δ ' + (e.meanRewardDelta == null ? '?' : Number(e.meanRewardDelta).toFixed(3));
	};
	o = s.option(form.DummyValue, '_holdout', _('Native Holdout'));
	o.cfgvalue = function() {
		var e = status.evidenceAggregate || (status.intelligence || {}).evidenceAggregate || {};
		return _('performed') + ': ' + (e.holdoutCount || 0) + ', ' + _('failures') + ': ' + (e.holdoutFailures || 0) + ' / ' + _('non-blocking');
	};
	o = s.option(form.DummyValue, '_fallback', _('Fallback Reason'));
	o.cfgvalue = function() { return status.fallbackReason || (status.intelligence || {}).lastResetReason || _('None'); };
	o = s.option(form.DummyValue, '_source_policy', _('Source Strategy Loop'));
	o.cfgvalue = function() {
		var p = status.sourcePolicy || diagnostics.sourcePolicy || {};
		return _('deterministic') + ': ' + (p.deterministic ? _('yes') : _('no')) + ', ' + _('requested') + ': ' + (p.requested || '?') + ', ' + _('effective') + ': ' + (p.effective || '?');
	};
	o = s.option(form.DummyValue, '_reuse_policy', _('Reuse / Full Optimize'));
	o.cfgvalue = function() {
		var r = status.reusePolicy || {};
		return _('Native hard gate') + ': ' + (r.actualPolicy || _('Unknown')) + ', ' + _('reason') + ': ' + (r.reason || _('none'));
	};
	o = s.option(form.DummyValue, '_efficiency', _('Probe Efficiency'));
	o.cfgvalue = function() { var e = status.efficiency || status.probeMetrics || {}; return _('probed') + ': ' + (e.candidatesProbed || 0) + ' / ' + (e.candidatesConsidered || 0) + ', ' + _('avoided') + ': ' + (e.avoidedProbes || 0) + ', ' + _('early stop') + ': ' + (e.earlyStopHit ? _('yes') : _('no')); };
	o = s.option(form.DummyValue, '_comparison', _('Native vs Rill'));
	o.cfgvalue = function() { var i = status.intelligence || {}; return _('native') + ': ' + (i.nativeReward == null ? '?' : i.nativeReward.toFixed(3)) + ', ' + _('Rill') + ': ' + (i.rillReward == null ? '?' : i.rillReward.toFixed(3)) + ', ' + _('regret') + ': ' + (i.shadowRegret == null ? 0 : i.shadowRegret.toFixed(3)); };
	o = s.option(form.DummyValue, '_prefix', _('Prefix Intelligence'));
	o.cfgvalue = function() { var p = diagnostics.prefixIntelligence || {}; return _('tracked') + ': ' + (p.trackedPrefixes || 0) + ', ' + _('high quality') + ': ' + ((p.recentHighQuality || []).length) + ', ' + _('low quality') + ': ' + ((p.recentLowQuality || []).length); };
	o = s.option(form.DummyValue, '_colo', _('Colo Intelligence'));
	o.cfgvalue = function() { var c = diagnostics.coloIntelligence || {}; return _('observed') + ': ' + (c.observedColoCount || 0) + ', ' + _('latest') + ': ' + (c.latestObservedColo || _('Unknown')) + ', ' + _('Unknown') + ': ' + (c.unknownCount || 0); };

	o = s.option(form.Button, '_self_check', _('Shadow Self-check'));
	o.inputtitle = _('Run self-check');
	o.inputstyle = 'apply';
	o.onclick = function() {
		var button = this;
		utils.setBusy(button, _('Checking...'));
		return callSelfCheck().then(function(result) {
			if (result && result.success)
				ui.addNotification(null, E('p', _('Rill self-check passed.')));
			else
				ui.addNotification(null, E('p', _('Rill self-check fell back to Native.')), 'warning');
		}).catch(function(error) {
			ui.addNotification(null, E('p', _('Unable to complete self-check: %s').format(error.message || error)), 'error');
		}).finally(function() { utils.resetBusy(button); });
	};
	o = s.option(form.Button, '_reset', _('Reset Learning State'));
	o.inputtitle = _('Reset learning state');
	o.inputstyle = 'reset';
	o.onclick = function() {
		if (!confirm(_('Reset Rill learning state? Native configuration will not be changed.')))
			return;
		var button = this;
		var generation = (status.intelligence || {}).stateGeneration || 0;
		utils.setBusy(button, _('Resetting...'));
		return callReset(generation).then(function(result) {
			if (!result || result.success !== true)
				throw new Error((result && result.error) || _('Reset rejected'));
			ui.addNotification(null, E('p', _('Rill learning state was reset.')), 'info');
		}).catch(function(error) {
			ui.addNotification(null, E('p', _('Unable to reset learning state: %s').format(error.message || error)), 'error');
		}).finally(function() { utils.resetBusy(button); });
	};

	return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
