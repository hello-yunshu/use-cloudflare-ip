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
			return Promise.resolve({});

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
	if (!result || result.success !== true)
		throw new Error(result.error || _('service action failed'));
	return result || {};
}

function loadSharedCSS() {
	if (!document.getElementById('cfi-shared-css')) {
		var link = E('link', {
			'id': 'cfi-shared-css',
			'rel': 'stylesheet',
			'href': L.resource('cloudflare-ip/cloudflare-ip.css') + '?v=@PKG_VERSION@'
		});
		document.head.appendChild(link);
	}
}

function footerSeparator(extraClass) {
	var className = 'ys-tool-footer-separator';
	if (extraClass)
		className += ' ' + extraClass;
	return E('span', { 'class': className }, '\u00a0·\u00a0');
}

function footerIcon(name) {
	var svgNS = 'http://www.w3.org/2000/svg';
	var svg = document.createElementNS(svgNS, 'svg');
	var path = document.createElementNS(svgNS, 'path');

	svg.setAttribute('class', 'ys-tool-footer-link-icon ' + name);
	svg.setAttribute('viewBox', '0 0 24 24');
	svg.setAttribute('width', '14');
	svg.setAttribute('height', '14');
	svg.setAttribute('aria-hidden', 'true');
	svg.setAttribute('focusable', 'false');
	svg.setAttribute('style', 'width:1em;height:1em;max-width:1em;max-height:1em;display:inline-block;flex:0 0 auto;vertical-align:-0.125em');

	if (name === 'github') {
		path.setAttribute('fill', 'currentColor');
		path.setAttribute('d', 'M12 2C6.48 2 2 6.58 2 12.26c0 4.53 2.87 8.37 6.84 9.73.5.09.68-.22.68-.49v-1.9c-2.78.62-3.37-1.22-3.37-1.22-.45-1.19-1.11-1.5-1.11-1.5-.91-.64.07-.63.07-.63 1 .07 1.53 1.06 1.53 1.06.9 1.57 2.35 1.12 2.92.86.09-.67.35-1.12.63-1.38-2.22-.26-4.56-1.14-4.56-5.07 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.36 9.36 0 0 1 12 6.97c.85 0 1.71.12 2.51.34 1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.94-2.34 4.8-4.57 5.06.36.32.68.94.68 1.9v2.82c0 .27.18.59.69.49A10.24 10.24 0 0 0 22 12.26C22 6.58 17.52 2 12 2z');
	} else if (name === 'x') {
		path.setAttribute('fill', 'currentColor');
		path.setAttribute('d', 'M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231 5.451-6.231zm-1.161 17.52h1.833L7.084 4.126H5.117L17.083 19.77z');
	} else {
		return null;
	}

	svg.appendChild(path);
	return svg;
}

function footerLink(href, label, icon) {
	var children = [];
	var iconNode = icon ? footerIcon(icon) : null;
	if (iconNode)
		children.push(iconNode);
	children.push(E('span', { 'class': 'ys-tool-footer-link-label' }, label));

	return E('a', {
		'class': 'ys-tool-footer-link' + (icon ? ' ' + icon : ''),
		'href': href,
		'target': '_blank',
		'rel': 'noopener noreferrer'
	}, children);
}

function renderFooter(options) {
	options = options || {};
	var project = options.project || 'Cloudflare IP Optimization';
	var version = options.version && options.version !== '-' ? 'v' + options.version : '';
	var repoUrl = options.repoUrl || 'https://github.com/hello-yunshu/use-cloudflare-ip';

	return E('footer', { 'class': 'ys-tool-footer' }, [
		E('div', { 'class': 'ys-tool-footer-brand' }, [
			E('span', { 'class': 'ys-tool-footer-mark' }, '云云舒'),
			footerSeparator('ys-tool-footer-title-separator'),
			E('span', { 'class': 'ys-tool-footer-title' }, project),
			version ? footerSeparator('ys-tool-footer-version-separator') : '',
			version ? E('span', { 'class': 'ys-tool-footer-version' }, version) : ''
		]),
		E('div', { 'class': 'ys-tool-footer-links' }, [
			E('span', { 'class': 'ys-tool-footer-project-link' }, footerLink(repoUrl, 'Project')),
			footerSeparator('ys-tool-footer-project-separator'),
			footerLink('https://github.com/hello-yunshu', 'GitHub', 'github'),
			footerSeparator(),
			footerLink('https://x.com/yunyunyshu', '@云云舒', 'x')
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
