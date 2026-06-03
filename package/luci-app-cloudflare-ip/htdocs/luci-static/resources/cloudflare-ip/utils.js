'use strict';
'require uci';
'require baseclass';

function safeApply() {
	return uci.apply().catch(function(e) {
		var message = e && e.message ? e.message : String(e);
		if (e === 5 || /\bubus code 5\b/.test(message) || /No data|未收到数据/.test(message))
			return;
		throw e;
	});
}

function setBusy(button, label) {
	if (!button)
		return;
	button.disabled = true;
	button.setAttribute('data-original-title', button.textContent);
	button.textContent = label;
}

function resetBusy(button) {
	if (!button)
		return;
	button.disabled = false;
	button.textContent = button.getAttribute('data-original-title') || button.textContent;
	button.removeAttribute('data-original-title');
}

function reloadSoon(delay) {
	window.setTimeout(function() {
		window.location.reload();
	}, delay || 1200);
}

function waitForServiceReady(callStatus, options) {
	options = options || {};
	var interval = options.interval || 3000;
	var timeout = options.timeout || 120000;
	var startedAt = Date.now();

	function wait(delay) {
		return new Promise(function(resolve) {
			window.setTimeout(resolve, delay);
		});
	}

	function poll() {
		if (options.isActive && !options.isActive())
			return {};

		return callStatus().then(function(status) {
			status = status || {};
			if (status.running && status.last_result !== 'running')
				return status;
			if (Date.now() - startedAt >= timeout)
				return status;
			return wait(interval).then(poll);
		});
	}

	return poll();
}

function requireSuccess(result) {
	if (result && result.success === false)
		throw new Error(result.error || _('service action failed'));
	return result || {};
}

function loadSharedCSS() {
	if (!document.getElementById('cfi-shared-css')) {
		var link = E('link', {
			'id': 'cfi-shared-css',
			'rel': 'stylesheet',
			'href': L.resource('cloudflare-ip/cloudflare-ip.css')
		});
		document.head.appendChild(link);
	}
}

function footerLink(href, label) {
	return E('a', {
		'class': 'ys-tool-footer-link',
		'href': href,
		'target': '_blank',
		'rel': 'noopener noreferrer'
	}, label);
}

function renderFooter(options) {
	options = options || {};
	var project = options.project || 'Cloudflare IP Optimization';
	var version = options.version && options.version !== '-' ? 'v' + options.version : '';
	var repoUrl = options.repoUrl || 'https://github.com/hello-yunshu/use-cloudflare-ip';

	return E('footer', { 'class': 'ys-tool-footer' }, [
		E('div', { 'class': 'ys-tool-footer-brand' }, [
			E('span', { 'class': 'ys-tool-footer-mark' }, 'Yunshu Lab'),
			E('span', { 'class': 'ys-tool-footer-title' }, project),
			version ? E('span', { 'class': 'ys-tool-footer-version' }, version) : ''
		]),
		E('div', { 'class': 'ys-tool-footer-links' }, [
			footerLink(repoUrl, 'Project'),
			footerLink('https://github.com/hello-yunshu', 'GitHub'),
			footerLink('https://x.com/yunyunyshu', 'X @yunyunyshu')
		])
	]);
}

function appendFooter(node, options) {
	loadSharedCSS();
	if (node)
		node.appendChild(renderFooter(options));
	return node;
}

function renderWithFooter(rendered, options) {
	return Promise.resolve(rendered).then(function(node) {
		return appendFooter(node, options);
	});
}

return baseclass.extend({
	safeApply: safeApply,
	setBusy: setBusy,
	resetBusy: resetBusy,
	reloadSoon: reloadSoon,
	waitForServiceReady: waitForServiceReady,
	requireSuccess: requireSuccess,
	loadSharedCSS: loadSharedCSS,
	renderFooter: renderFooter,
	appendFooter: appendFooter,
	renderWithFooter: renderWithFooter
});
