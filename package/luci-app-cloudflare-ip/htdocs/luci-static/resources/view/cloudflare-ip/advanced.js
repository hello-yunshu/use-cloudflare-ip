'use strict';
'require view';
'require ui';
'require rpc';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

return view.extend({
	title: _('Advanced'),

	load: function() {
		return uci.load('cf_ip');
	},

	render: function() {
		utils.loadSharedCSS();
		var m, s, o;

		m = new form.Map('cf_ip', _('Advanced'));

		/* Self Update: 2.x is package-managed; keep the old keys readable but do
		 * not expose a button that claims to replace one script safely. */
		s = m.section(form.TypedSection, 'service', _('Script Updates'));
		s.anonymous = true;

		o = s.option(form.Flag, 'auto_update', _('Auto Update Script'),
			_('Deprecated in 2.x. Package upgrades are required to update the engine.'));
		o.default = '0';
		o.rmempty = false;
		o.readonly = true;

		o = s.option(form.Value, 'self_update_url', _('Script Update URL'),
			_('Retained only for migration compatibility; it is not used by the 2.x engine.'));
		o.placeholder = 'https://raw.githubusercontent.com/...';
		o.rmempty = false;
		o.datatype = 'string';
		o = s.option(form.DummyValue, '_self_update_note', _('Update policy'));
		o.cfgvalue = function() { return _('Deprecated / package-managed'); };

		/* Download */
		s = m.section(form.TypedSection, 'service', _('Download'));
		s.anonymous = true;

		o = s.option(form.Value, 'github_mirror', _('GitHub Mirror'),
			_('GitHub download proxy URL. Leave empty for direct downloads. Must end with /.'));
		o.placeholder = 'https://ghp.ci/';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Value, 'download_retries', _('Download Retries'),
			_('Number of retry attempts for GitHub downloads.'));
		o.datatype = 'range(1,10)';
		o.placeholder = '3';
		o.rmempty = false;

		o = s.option(form.Value, 'download_retry_delay', _('Retry Delay (seconds)'),
			_('Seconds to wait between download retries.'));
		o.datatype = 'range(1,60)';
		o.placeholder = '5';
		o.rmempty = false;

		/* Startup */
		s = m.section(form.TypedSection, 'service', _('Startup'));
		s.anonymous = true;

		o = s.option(form.Value, 'startup_delay', _('Startup Delay'),
			_("Random delay upper bound (seconds). Empty/random = 0~300s, 0 = no delay."));
		o.placeholder = 'random';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Flag, 'verbose', _('Verbose Logging'),
			_('Output detailed progress logs.'));
		o.default = '0';

		o = s.option(form.Value, 'work_dir', _('Work Directory'),
			_('Leave empty to use the script directory.'));
		o.placeholder = '/root/cf-ip';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Value, 'measurement_timeout', _('Measurement Deadline (seconds)'),
			_('Measurement deadline for stop, CFST, probes, apply and normal restart. Recovery has a separate deadline.'));
		o.datatype = 'range(20,300)';
		o.default = '60';
		o.rmempty = false;

		o = s.option(form.Value, 'recovery_timeout', _('Recovery Deadline (seconds)'),
			_('Independent fail-safe deadline for rollback, restoring service state and recovery health checks. Allowed: 10-120 seconds.'));
		o.datatype = 'range(10,120)';
		o.default = '30';
		o.rmempty = false;

		o = s.option(form.Value, 'probe_top_count', _('Probe Top Candidates'),
			_('Number of CFST results to verify against every target domain before ranking.'));
		o.datatype = 'range(1,32)';
		o.default = '8';
		o.rmempty = false;

		o = s.option(form.Value, 'probe_concurrency', _('Probe Concurrency'),
			_('Concurrent target-domain probes, bounded to protect the proxy-off window.'));
		o.datatype = 'range(1,16)';
		o.default = '4';
		o.rmempty = false;

		o = s.option(form.Value, 'probe_timeout', _('Probe Timeout (seconds)'),
			_('Per-domain probe timeout; the global hard limit still wins.'));
		o.datatype = 'range(1,30)';
		o.default = '5';
		o.rmempty = false;

		utils.createHandleSave(m);
		utils.createHandleSaveApply(m);

		return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
