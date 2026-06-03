'use strict';
'require view';
'require ui';
'require rpc';
'require dom';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

var callStatus = rpc.declare({ object: 'cf_ip', method: 'status', expect: { '': {} } });
var callServiceRestart = rpc.declare({ object: 'cf_ip', method: 'restart', expect: { '': {} } });

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			callStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var env = data[1] || {};
		var passwallInstalled = env.passwall_installed || false;
		var openclashInstalled = env.openclash_installed || false;

		var m, s, o;

		m = new form.Map('cf_ip', _('Cloudflare IP Optimization'),
			_('Configure the Cloudflare IP speed test and optimization service.'));

		s = m.section(form.TypedSection, 'service', _('Service'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable Service'),
			_('Run the background service to periodically optimize Cloudflare IPs.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'cron_interval', _('Run Interval (minutes)'),
			_('How often the service runs speed tests. Recommended: 360 (6 hours). Avoid below 60.'));
		o.datatype = 'range(30,1440)';
		o.placeholder = '360';
		o.rmempty = false;

		s = m.section(form.TypedSection, 'service', _('Speed Test'));
		s.anonymous = true;

		o = s.option(form.ListValue, 'mode', _('Mode'),
			_('Select which proxy service to update.'));
		if (passwallInstalled)
			o.value('passwall', 'PassWall');
		if (openclashInstalled)
			o.value('openclash', 'OpenClash');
		if (!passwallInstalled && !openclashInstalled) {
			o.value('passwall', 'PassWall');
			o.value('openclash', 'OpenClash');
		}
		o.default = passwallInstalled ? 'passwall' : (openclashInstalled ? 'openclash' : 'passwall');
		o.rmempty = false;

		o = s.option(form.Value, 'ip_count', _('IP Count'),
			_('Number of best IPs to keep. If fewer IPs found, the fastest one is reused.'));
		o.datatype = 'range(1,20)';
		o.placeholder = '4';
		o.rmempty = false;

		o = s.option(form.ListValue, 'ip_type', _('IP Type'),
			_('Select which IP addresses to test.'));
		o.value('ipv4', 'IPv4');
		o.value('ipv6', 'IPv6');
		o.value('both', 'Both');
		o.default = 'ipv4';
		o.rmempty = false;

		o = s.option(form.ListValue, 'speedtest_protocol', _('Speed Test Protocol'),
			_('TCPing measures TCP latency. HTTPing measures HTTP response latency and supports data center filtering.'));
		o.value('tcp', 'TCPing');
		o.value('http', 'HTTPing');
		o.default = 'tcp';
		o.rmempty = false;

		o = s.option(form.Value, 'speedtest_cfcolo', _('Data Center Filter'),
			_('Filter by Cloudflare data center in HTTPing mode. Comma-separated, e.g. HKG,NRT,LAX. Only effective with HTTPing.'));
		o.placeholder = 'HKG,NRT,LAX';
		o.depends('speedtest_protocol', 'http');

		o = s.option(form.Value, 'speedtest_dn', _('Download Test Count'),
			_('Number of IPs to test download speed.'));
		o.datatype = 'range(1,100)';
		o.placeholder = '10';
		o.rmempty = false;

		o = s.option(form.Value, 'speedtest_tll', _('Average Latency Limit (ms)'),
			_('Skip IPs with average latency above this limit.'));
		o.datatype = 'range(1,1000)';
		o.placeholder = '40';
		o.rmempty = false;

		o = s.option(form.Flag, 'stop_service', _('Stop Service Before Test'),
			_('Stop the proxy service before speed testing to avoid interference, and restart after updating.'));
		o.default = '1';
		o.rmempty = false;

		m.handleSave = function(ev) {
			var tasks = [];
			document.getElementById('maincontent')
				.querySelectorAll('.cbi-map').forEach(function(map) {
					tasks.push(dom.callClassMethod(map, 'save'));
				});
			return Promise.all(tasks);
		};

		m.handleSaveApply = function(ev, mode) {
			return this.handleSave(ev).then(function() {
				return utils.safeApply();
			}).then(function() {
				return uci.load('cf_ip');
			}).then(function() {
				if (uci.get('cf_ip', 'main', 'enabled') !== '1') {
					ui.addNotification(null, E('p', _('Configuration saved and applied.')), 'info');
					utils.reloadSoon(600);
					return;
				}

				ui.addNotification(null, E('p', _('Configuration saved. Restarting service...')), 'info');
				return callServiceRestart().then(utils.requireSuccess).then(function() {
					return utils.waitForServiceReady(callStatus);
				}).then(function(status) {
					ui.addNotification(null, E('p', _('Configuration applied and service is ready.')), 'info');
					utils.reloadSoon(300);
				});
			}).catch(function(e) {
				ui.addNotification(null, E('p', _('Failed to apply configuration: ') + e.message), 'error');
			});
		};

		return m.render();
	}
});
