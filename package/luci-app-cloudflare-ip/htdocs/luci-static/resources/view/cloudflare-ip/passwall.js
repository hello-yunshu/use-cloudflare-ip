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
	title: _('PassWall'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			callStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var env = data[1] || {};

		if (!env.passwall_installed) {
			return E('div', { 'class': 'cbi-map' }, [
				E('div', { 'class': 'cbi-section' },
					E('h3', {}, _('PassWall Not Found')),
					E('p', {}, _('PassWall is not installed. Please install PassWall before using this feature.'))
				)
			]);
		}

		utils.loadSharedCSS();

		var m = new form.Map('cf_ip', _('PassWall'));

		var s = m.section(form.TypedSection, 'passwall', _('PassWall Settings'));
		s.anonymous = true;

		var o;

		o = s.option(form.Value, 'target_domain', _('Target Domain'));
		o.description = _('Only PassWall nodes whose address equals this domain will be updated. Comma-separated for multiple domains.');
		o.placeholder = 'cdn.example.com';
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'name_suffix', _('Node Name Suffix'));
		o.description = _('Suffix appended to the original node name. Placeholders: {n} = sequence number, {ip} = IP address. Leave empty to keep original names.');
		o.placeholder = ' [CF-{n}]';
		o.rmempty = true;

		var ss = m.section(form.TypedSection, 'passwall', _('Sync Schedule'));
		ss.anonymous = true;

		o = ss.option(form.ListValue, 'sync_interval', _('Sync Schedule'),
			_('How often to sync Cloudflare best IPs to PassWall. When set to "Follow main program", uses the same schedule as the main speedtest service.'));
		o.value('', _('Follow main program'));
		o.value('6h', _('Every 6 hours (recommended)'));
		o.value('1h', _('Every hour'));
		o.value('30m', _('Every 30 minutes'));
		o.value('15m', _('Every 15 minutes'));
		o.value('0 3 * * *', _('Daily at 3:00 AM'));
		o.value('0 3,15 * * *', _('Daily at 3:00 AM & 3:00 PM'));
		o.value('0 */6 * * *', _('Every 6 hours at :00'));
		o.value('custom', _('Custom...'));
		o.default = '';
		o.rmempty = true;
		o.optional = true;

		o = ss.option(form.Value, 'sync_custom', _('Custom Sync Schedule'),
			_('Enter a cron-compatible duration (e.g. 6h, 30m) or a 5-field crontab expression. Comma-separated lists supported (e.g. 0 3,6 * * *).'));
		o.placeholder = '6h';
		o.depends('sync_interval', 'custom');
		o.rmempty = true;
		o.optional = true;

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
