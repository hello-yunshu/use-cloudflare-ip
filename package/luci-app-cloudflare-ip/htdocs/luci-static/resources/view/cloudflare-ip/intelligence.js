'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require cloudflare-ip/utils as utils';

var callStatus = rpc.declare({ object: 'cf_ip', method: 'status', expect: { '': {} } });

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
			callStatus().catch(function() { return { _statusError: true }; })
		]);
	},

	render: function(data) {
		utils.loadSharedCSS();
		data = data || [];
		var status = data[1] || {};
		var m = new form.Map('cf_ip', _('Rill Intelligence'),
			_('The generic Rill Runtime is supplied by OpenWrt packaging. Cloudflare IP owns candidate validation, ranking policy, reward and proxy transactions.'));
		var s, o;

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
		o.description = _('Assisted is currently qualification-gated and falls back to Shadow; Native ranking remains authoritative.');
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

		return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
