'use strict';
'require view';
'require ui';
'require rpc';
'require form';
'require uci';
'require cloudflare-ip/utils as utils';

var callOcListBackups = rpc.declare({ object: 'cf_ip', method: 'oc-list-backups', expect: { '': {} } });
var callOcRestoreBackup = rpc.declare({ object: 'cf_ip', method: 'oc-restore-backup', params: ['id'], expect: { '': {} } });
var callOcDeleteBackup = rpc.declare({ object: 'cf_ip', method: 'oc-delete-backup', params: ['id'], expect: { '': {} } });

function formatSize(bytes) {
	if (!bytes || bytes <= 0) return '-';
	if (bytes < 1024) return bytes + ' B';
	if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
	return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

return view.extend({
	title: _('OpenClash'),

	load: function() {
		return Promise.all([
			uci.load('cf_ip'),
			utils.callStatus().catch(function() { return {}; }),
			callOcListBackups().catch(function() { return { success: false, backups: [] }; })
		]);
	},

	render: function(data) {
		var env = data[1] || {};
		var backupData = data[2] || {};

		if (!env.openclash_installed) {
			return E('div', { 'class': 'cbi-map' }, [
				E('div', { 'class': 'cbi-section' },
					E('h3', {}, _('OpenClash Not Found')),
					E('p', {}, _('OpenClash is not installed. Please install OpenClash before using this feature.'))
				)
			]);
		}

		utils.loadSharedCSS();

		var m = new form.Map('cf_ip', _('OpenClash'));

		var s = m.section(form.TypedSection, 'openclash', _('OpenClash Settings'));
		s.anonymous = true;

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

		utils.createHandleSave(m);
		utils.createHandleSaveApply(m);

		/* Build backup section as a separate DOM tree appended after the form */
		var backupSection = E('div', { 'class': 'cbi-section cfi-section', 'id': 'oc-backups-section' });
		backupSection.appendChild(E('h3', {}, _('Config Backups')));

		var backups = (backupData.success !== false && backupData.backups) ? backupData.backups : [];

		if (backups.length === 0) {
			backupSection.appendChild(E('div', {
				'style': 'color:var(--subtext-color);font-style:italic;padding:0.5em 0'
			}, _('No backups available. Backups are created automatically when the config is updated.')));
		} else {
			var headers = [_('Backup Time'), _('Size'), _('Actions')];
			var table = E('table', { 'class': 'table cfi-responsive-table' });
			var thead = E('thead');
			var headerRow = E('tr');
			headers.forEach(function(title) {
				headerRow.appendChild(E('th', {}, title));
			});
			thead.appendChild(headerRow);
			table.appendChild(thead);

			var tbody = E('tbody');

			backups.forEach(function(backup) {
				var row = E('tr');
				row.appendChild(E('td', { 'data-label': headers[0] }, backup.timestamp || backup.id || '-'));
				row.appendChild(E('td', { 'data-label': headers[1] }, formatSize(backup.size)));

				var actionsCell = E('td', { 'class': 'cfi-actions', 'data-label': headers[2] });

				actionsCell.appendChild(E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': function() {
						ui.showModal(_('Confirm Restore'), [
							E('div', { 'class': 'alert-message warning' },
								_('Are you sure you want to restore this backup? A backup of the current configuration will be created first.')),
							E('div', { 'class': 'right' }, [
								E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); } }, _('Cancel')),
								E('button', {
									'class': 'cbi-button cbi-button-apply',
									'click': function() {
										ui.hideModal();
										ui.showModal(_('Restoring...'), [E('p', {}, _('Please wait...'))]);
										callOcRestoreBackup(backup.id).then(function(result) {
											ui.hideModal();
											if (result && result.error) {
												ui.addNotification(null, E('p', {}, _('Restore failed') + ': ' + result.error), 'error');
											} else {
												ui.addNotification(null, E('p', {}, _('Backup restored successfully.')), 'info');
												setTimeout(function() { location.reload(); }, 500);
											}
										}).catch(function(e) {
											ui.hideModal();
											ui.addNotification(null, E('p', {}, _('Restore failed: ') + e.message), 'error');
										});
									}
								}, '\u21A9 ' + _('Restore'))
							])
						]);
					}
				}, '\u21A9 ' + _('Restore')));

				actionsCell.appendChild(E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': function() {
						ui.showModal(_('Confirm Delete'), [
							E('p', {}, _('Are you sure you want to delete this backup?')),
							E('div', { 'class': 'right' }, [
								E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); } }, _('Cancel')),
								E('button', {
									'class': 'cbi-button cbi-button-reset',
									'click': function() {
										ui.hideModal();
										callOcDeleteBackup(backup.id).then(function(result) {
											if (result && result.error) {
												ui.addNotification(null, E('p', {}, result.error), 'error');
											} else {
												ui.addNotification(null, E('p', {}, _('Backup deleted')), 'info');
												setTimeout(function() { location.reload(); }, 500);
											}
										}).catch(function(e) {
											ui.addNotification(null, E('p', {}, e.message), 'error');
										});
									}
								}, _('Delete'))
							])
						]);
					}
				}, _('Delete')));

				row.appendChild(actionsCell);
				tbody.appendChild(row);
			});

			table.appendChild(tbody);
			backupSection.appendChild(E('div', { 'class': 'cfi-table-wrap' }, table));
		}

		return utils.renderWithFooter(m.render().then(function(node) {
			/* Append backup section after the form */
			node.appendChild(backupSection);
			return node;
		}), utils.FOOTER_OPTIONS);
	}
});
