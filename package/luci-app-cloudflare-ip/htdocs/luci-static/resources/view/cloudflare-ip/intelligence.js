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
			callDiagnostics().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		utils.loadSharedCSS();
		data = data || [];
		var status = data[1] || {};
		var diagnostics = data[2] || {};
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
	o = s.option(form.DummyValue, '_fallback', _('Fallback Reason'));
	o.cfgvalue = function() { return status.fallbackReason || (status.intelligence || {}).lastResetReason || _('None'); };
	o = s.option(form.DummyValue, '_source_policy', _('Source Strategy Loop'));
	o.cfgvalue = function() {
		var p = status.sourcePolicy || diagnostics.sourcePolicy || {}, q = status.sourcePolicyQualification || diagnostics.sourcePolicyQualification || {};
		return _('requested') + ': ' + (p.requested || p.policy || '?') + ', ' + _('executed') + ': ' + (p.executed || p.effective || '?') + ', ' + _('recommended') + ': ' + (p.recommended || '?') + ', ' + _('qualification') + ': ' + (q.qualificationState || q.state || _('learning')) + ', ' + _('attribution') + ': ' + (q.attributionCoverage == null ? '?' : (q.attributionCoverage * 100).toFixed(0) + '%') + ', ' + _('downgrade') + ': ' + (q.downgradeReason || _('none'));
	};
	o = s.option(form.DummyValue, '_reuse_policy', _('Reuse / Full Optimize'));
	o.cfgvalue = function() {
		var r = status.reusePolicy || {};
		return _('actual') + ': ' + (r.actualAction || _('unknown')) + ', ' + _('recommended') + ': ' + (r.recommendedAction || _('unknown')) + ', ' + _('reason') + ': ' + (r.reason || _('none'));
	};
	o = s.option(form.DummyValue, '_efficiency', _('Probe Efficiency'));
	o.cfgvalue = function() { var e = status.efficiency || status.probeMetrics || {}; return _('probed') + ': ' + (e.candidatesProbed || 0) + ' / ' + (e.candidatesConsidered || 0) + ', ' + _('avoided') + ': ' + (e.avoidedProbes || 0) + ', ' + _('early stop') + ': ' + (e.earlyStopHit ? _('yes') : _('no')); };
	o = s.option(form.DummyValue, '_comparison', _('Native vs Rill'));
	o.cfgvalue = function() { var i = status.intelligence || {}; return _('native') + ': ' + (i.nativeReward == null ? '?' : i.nativeReward.toFixed(3)) + ', ' + _('Rill') + ': ' + (i.rillReward == null ? '?' : i.rillReward.toFixed(3)) + ', ' + _('regret') + ': ' + (i.shadowRegret == null ? 0 : i.shadowRegret.toFixed(3)); };
	o = s.option(form.DummyValue, '_prefix', _('Prefix Intelligence'));
	o.cfgvalue = function() { var p = diagnostics.prefixIntelligence || {}; return _('tracked') + ': ' + (p.trackedPrefixes || 0) + ', ' + _('high quality') + ': ' + ((p.recentHighQuality || []).length) + ', ' + _('low quality') + ': ' + ((p.recentLowQuality || []).length); };
	o = s.option(form.DummyValue, '_colo', _('Colo Intelligence'));
	o.cfgvalue = function() { var c = diagnostics.coloIntelligence || {}; return _('observed') + ': ' + (c.observedColoCount || 0) + ', ' + _('latest') + ': ' + (c.latestObservedColo || _('unknown')) + ', ' + _('unknown') + ': ' + (c.unknownCount || 0); };

	o = s.option(form.Button, '_self_check', _('Shadow Self-check'));
	o.inputtitle = _('Run now');
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
			ui.addNotification(null, E('p', _('Self-check failed: ') + (error.message || error)), 'error');
		}).finally(function() { utils.resetBusy(button); });
	};
	o = s.option(form.Button, '_reset', _('Reset Learning State'));
	o.inputtitle = _('Reset');
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
			ui.addNotification(null, E('p', _('Reset failed: ') + (error.message || error)), 'error');
		}).finally(function() { utils.resetBusy(button); });
	};

	return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
