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
	title: _('Cloudflare IP - PassWall'),

	load: function() {
		return uci.load('cf_ip');
	},

	render: function() {
		utils.loadSharedCSS();

		var m = new form.Map('cf_ip', _('Cloudflare IP - PassWall'));

		var s = m.section(form.TypedSection, 'passwall', _('PassWall Settings'));
		s.anonymous = true;

		var info = s.option(form.DummyValue, '_info', '');
		info.rawhtml = true;
		info.cfgvalue = function() {
			return '<div class="cbi-section-descr cfi-cmd-box">' +
				_('PassWall mode scans uci show passwall and updates nodes whose address matches the target domain with optimized IPs.') +
				'</div>';
		};

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
