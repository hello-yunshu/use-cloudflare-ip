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
		utils.loadSharedCSS();
		var env = data[1] || {};
		var passwallInstalled = env.passwall_installed || false;
		var openclashInstalled = env.openclash_installed || false;

		var m, s, o;

		m = new form.Map('cf_ip', _('Settings'),
			_('Configure the Cloudflare IP speed test and optimization service.'));

		s = m.section(form.TypedSection, 'service', _('Service'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable Service'),
			_('Run the background service to periodically optimize Cloudflare IPs.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.ListValue, 'cron_interval', _('Run Schedule'),
			_('Select how often the speed test runs. The service computes the next run time automatically.'));
		o.value('6h', _('Every 6 hours (recommended)'));
		o.value('1h', _('Every hour'));
		o.value('30m', _('Every 30 minutes'));
		o.value('15m', _('Every 15 minutes'));
		o.value('0 3 * * *', _('Daily at 3:00 AM'));
		o.value('0 3,15 * * *', _('Daily at 3:00 AM & 3:00 PM'));
		o.value('0 */6 * * *', _('Every 6 hours at :00'));
		o.value('custom', _('Custom...'));
		o.default = '6h';
		o.rmempty = false;

		o = s.option(form.Value, 'cron_custom', _('Custom Schedule'),
			_('Enter a duration (e.g. 6h, 30m, 1h30m) or a 5-field crontab expression. Comma-separated lists supported (e.g. 0 3,6 * * *).'));
		o.placeholder = '6h';
		o.depends('cron_interval', 'custom');

		s = m.section(form.TypedSection, 'service', _('Speed Test'));
		s.anonymous = true;

		o = s.option(form.ListValue, 'mode', _('Mode'),
			_('Select which proxy service to update.'));
		if (passwallInstalled)
			o.value('passwall', 'PassWall');
		if (openclashInstalled)
			o.value('openclash', 'OpenClash');
		if (!passwallInstalled && !openclashInstalled) {
			o.value('none', _('None (No proxy service detected)'));
			o.description = _('PassWall or OpenClash is not installed. Please install one before using this service.');
		}
		o.default = passwallInstalled ? 'passwall' : (openclashInstalled ? 'openclash' : 'none');
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
		o.value('both', _('Both'));
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

		o = s.option(form.Flag, 'cfst_persist', _('Keep CFST Across Upgrades'),
			_('Preserve CFST binary during OpenWrt sysupgrade so it survives system upgrades.'));
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

		return utils.renderWithFooter(m.render(), {
			project: 'Cloudflare IP Optimization',
			repoUrl: 'https://github.com/hello-yunshu/use-cloudflare-ip'
		});
	}
});
