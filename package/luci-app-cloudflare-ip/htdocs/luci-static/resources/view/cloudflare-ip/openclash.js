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
	title: _('Cloudflare IP - OpenClash'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			callStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var env = data[1] || {};

		if (!env.openclash_installed) {
			return E('div', { 'class': 'cbi-map' }, [
				E('div', { 'class': 'cbi-section' },
					E('h3', {}, _('OpenClash Not Found')),
					E('p', {}, _('OpenClash is not installed. Please install OpenClash before using this feature.'))
				)
			]);
		}

		utils.loadSharedCSS();

		var m = new form.Map('cf_ip', _('Cloudflare IP - OpenClash'));

		var s = m.section(form.TypedSection, 'openclash', _('OpenClash Settings'));
		s.anonymous = true;

		var info = s.option(form.DummyValue, '_info', '');
		info.rawhtml = true;
		info.cfgvalue = function() {
			return '<div class="cbi-section-descr cfi-cmd-box">' +
				_('OpenClash mode modifies the YAML configuration file. It finds proxies whose server matches the target domain, generates [CF-1], [CF-2] variants, and keeps servername/Host as the original domain. Supports vless/vmess/trojan with tls:true or network ws/xhttp/grpc/h2/http.') +
				'</div>';
		};

		var o;

		o = s.option(form.Value, 'config', _('Config File Path'));
		o.description = _('Path to the OpenClash YAML configuration file.');
		o.placeholder = '/etc/openclash/config/config.yaml';
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'target_domain', _('Target Domain'));
		o.description = _('Only OpenClash proxies whose server matches this domain will be updated. Comma-separated for multiple domains.');
		o.placeholder = 'cdn.example.com';
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'name_suffix', _('Proxy Name Suffix'));
		o.description = _('Suffix appended to the original proxy name. Placeholders: {n} = sequence number, {ip} = IP address. Leave empty to keep original names.');
		o.placeholder = ' [CF-{n}]';
		o.rmempty = true;

		o = s.option(form.Value, 'transport_filter', _('Transport Filter'));
		o.description = _('Only update proxies with the specified transport protocol. Comma-separated. Values: ws, grpc, xhttp, h2, http. Leave empty to update all supported proxies.');
		o.placeholder = 'ws,xhttp';
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Value, 'backup_count', _('Backup Count'));
		o.description = _('Number of OpenClash config backups to keep.');
		o.datatype = 'range(1,20)';
		o.placeholder = '3';
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
