'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require cloudflare-ip/utils as utils';

var callRegistry = rpc.declare({object:'cf_ip', method:'source-registry', expect:{'':{}}});
var callStatus = rpc.declare({object:'cf_ip', method:'source-status', expect:{'':{}}});
var callRefresh = rpc.declare({object:'cf_ip', method:'source-refresh', expect:{'':{}}});

function statusMap(rows) {
  var out={}; (rows||[]).forEach(function(x){ out[x.id]=x; }); return out;
}

return view.extend({
  load:function(){ return Promise.all([uci.load('cf_ip'),callRegistry().catch(function(){return{};}),callStatus().catch(function(){return{};})]); },
  render:function(data){
    utils.loadSharedCSS();
    var reg=(data[1]&&data[1].presets)||[], st=statusMap((data[2]&&data[2].sources)||[]), m=new form.Map('cf_ip',_('Candidate Sources')),s,o;
    s=m.section(form.TypedSection,'service',_('Candidate Budget'));
    s.anonymous=true;
    o=s.option(form.Value,'candidate_budget',_('CFST Candidate IP Count'),_('Maximum unique IPs supplied to one CFST run. Allocation is automatic: a small local-history share, a majority community share, and the remainder official-range exploration; unused quota flows to the other pools.'));
    o.datatype='range(100,512)'; o.default='128'; o.rmempty=false;
    o=s.option(form.MultiValue,'builtin_sources',_('Built-in Sources'),_('Official sources are authoritative ranges. Community sources are untrusted seed IPs and are always re-tested locally.'));
    reg.forEach(function(x){
      var group=x.group==='official'?_('Official'):x.group==='carrier'?_('Carrier-specific'):x.group==='measured'?_('Measured Seeds'):_('Recommended Community');
      o.value(x.id,group+' · '+x.name);
    });
    o.rmempty=false;

    s=m.section(form.GridSection,'source',_('Custom Sources'),_('Custom sources accept HTTPS text lists containing IP, IP:port, IPv6, bracketed IPv6:port, or CIDR. Only the IP/CIDR is retained; domains are rejected.'));
    s.addremove=true; s.anonymous=false;
    o=s.option(form.Flag,'enabled',_('Enabled')); o.default='1'; o.rmempty=false;
    o=s.option(form.Value,'name',_('Name')); o.rmempty=false;
    o=s.option(form.ListValue,'kind',_('Kind')); o.value('url',_('HTTPS URL')); o.value('manual',_('Manual IP list')); o.default='url';
    o=s.option(form.Value,'url',_('URL')); o.depends('kind','url'); o.placeholder='https://example.com/ip.txt';
    o=s.option(form.DynamicList,'ip',_('Manual IP / CIDR')); o.depends('kind','manual');
    o=s.option(form.ListValue,'family',_('Family')); o.value('auto',_('Auto')); o.value('ipv4','IPv4'); o.value('ipv6','IPv6'); o.default='auto';

    s=m.section(form.TypedSection,'lan',_('LAN Result Publisher'),_('Optional compatibility output for other LAN tools. PassWall/OpenClash still use direct modification and do not need this.'));
    s.anonymous=true;
    o=s.option(form.Flag,'enabled',_('Enable LAN Publisher'));o.default='0';o.rmempty=false;
    o=s.option(form.Value,'bind_address',_('Bind IPv4'),_('Leave empty to use the current LAN IPv4 automatically. Public or 0.0.0.0 bindings are refused.'));o.placeholder=_('LAN auto-detect');
    o=s.option(form.Value,'port',_('HTTP Port'));o.datatype='range(1024,65535)';o.default='12345';
    o=s.option(form.DummyValue,'_paths',_('Published Paths'));o.cfgvalue=function(){return '/ip.txt · /best-ipv4.txt · /best-ipv6.txt · /result.json';};

    var box=E('div',{'class':'cbi-section'},[
      E('h3',{},_('Runtime Source Status')),
      E('p',{},_('Each run allocates roughly 1/8 to fresh history champions, 5/8 to community seeds, and 1/4 to Cloudflare official range exploration. Missing pools flow to other sources. All candidates are deduplicated and measured locally in one CFST run; community ports are never reused.')),
      E('div',{'class':'cfi-table-wrap'}, E('div',{'class':'table'},[
        E('div',{'class':'tr table-titles'},[
          E('div',{'class':'th'},_('Source')),
          E('div',{'class':'th'},_('State')),
          E('div',{'class':'th'},_('Candidates')),
          E('div',{'class':'th'},_('Last Error'))
        ])
      ]))
    ]), table=box.lastChild.firstChild;
    var seen={};
    reg.forEach(function(x){ var q=st[x.id]||{}, state=q.success?(q.stale?_('Cached / stale'):_('Fresh')):_('Not fetched'); seen[x.id]=true; table.appendChild(E('div',{'class':'tr'},[
      E('div',{'class':'td','data-label':_('Source')},x.name),
      E('div',{'class':'td','data-label':_('State')},state),
      E('div',{'class':'td','data-label':_('Candidates')},String(q.parsedCount||0)),
      E('div',{'class':'td','data-label':_('Last Error')},q.lastError||'—')
    ])); });
    Object.keys(st).filter(function(id){return !seen[id];}).sort().forEach(function(id){var q=st[id],state=q.success?(q.stale?_('Cached / stale'):_('Fresh')):_('Error');table.appendChild(E('div',{'class':'tr'},[
      E('div',{'class':'td','data-label':_('Source')},id),
      E('div',{'class':'td','data-label':_('State')},state),
      E('div',{'class':'td','data-label':_('Candidates')},String(q.parsedCount||0)),
      E('div',{'class':'td','data-label':_('Last Error')},q.lastError||'—')
    ]));});
    box.appendChild(E('button',{'class':'btn cbi-button-action','click':function(){return callRefresh().then(function(r){ui.addNotification(null,E('p',{},r.success?_('Sources refreshed; candidate pool prepared.'):_('Source refresh failed.')),r.success?'info':'error'); setTimeout(function(){location.reload();},500);});}},_('Refresh Sources Now')));
    return utils.renderWithFooter(m.render().then(function(node){ node.appendChild(box); return node; }), utils.FOOTER_OPTIONS);
  }
});
