'use strict';
'require view';
'require ui';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

return view.extend({
	title: _('PassWall'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			utils.callStatus().catch(function() { return {}; })
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

		utils.createHandleSave(m);
		utils.createHandleSaveApply(m);

		return utils.renderWithFooter(m.render(), utils.FOOTER_OPTIONS);
	}
});
