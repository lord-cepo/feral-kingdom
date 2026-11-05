const base = JSON.parse(document.querySelector('#catalogue').textContent);
const storageKey = 'feral-kingdom-unit-catalogue-v1';
const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const editable = ['name','life','deployment','effects','hover','kind'];
const aliases = {walk:'move', skull:'die', death:'die', life:'heart', bomb_throw:'bomb', mending:'heart'};
let units = structuredClone(base.units), editing = false, sortKey = 'name', direction = 1;

function original(unit) { return base.units.find(row => row.id === unit.id); }
function changed(unit) { const row = original(unit); return !row || editable.some(key => unit[key] !== row[key]); }

// Whitelist imported fields; saved/imported content never supplies HTML or implementation status.
function mergeRecords(records) {
  let count = 0;
  for (const value of records) {
    if (!value || typeof value.id !== 'string') continue;
    let unit = units.find(row => row.id === value.id);
    if (!unit && value.custom === true && value.id.startsWith('custom-')) {
      unit = {id:value.id,name:'New unit',life:1,kind:'Troop',deployment:'Starting',effects:'',hover:'',custom:true,implemented:false,in_roster:false,aliases:'',portrait:'',richEffects:[]};
      units.push(unit);
    }
    if (!unit) continue;
    for (const key of ['name','deployment','effects','hover']) if (typeof value[key] === 'string') unit[key] = value[key];
    if (Number.isInteger(value.life) && value.life > 0) unit.life = value.life;
    if (['Hero','Troop','Temple'].includes(value.kind)) unit.kind = value.kind;
    count++;
  }
  return count;
}
try { const saved = JSON.parse(localStorage.getItem(storageKey) || 'null'); if (Array.isArray(saved)) mergeRecords(saved); } catch {}

function records() {
  return units.map(({id,name,kind,life,deployment,effects,hover,in_roster,implemented,aliases,custom}) => ({id,name,kind,life,deployment,effects,hover,in_roster,implemented,aliases,custom:!!custom}));
}
function save() {
  try { localStorage.setItem(storageKey, JSON.stringify(records())); $('#status').textContent = 'Working copy saved in this browser. Export JSON for a portable backup. Game definitions are unchanged.'; }
  catch { $('#status').textContent = 'Changes are kept in this tab. Export JSON to save them.'; }
}

// Render explicit icon tokens, while escaping every other part of user-authored text.
function renderTokens(value) {
  const source = String(value ?? ''), pattern = /\(([a-z][a-z _-]*)\)/gi;
  let output = '', offset = 0;
  for (const found of source.matchAll(pattern)) {
    output += esc(source.slice(offset, found.index));
    const token = found[1].toLowerCase().trim().replaceAll(' ', '_'), key = aliases[token] || token;
    const image = base.iconData[key];
    if (image) {
      let tip = base.glossary[key] || found[1];
      const markers = source.slice(0, found.index).match(/(?<![A-Za-z])(?:[XY])?([FTPA]+)[ \t]*$/);
      if (markers) for (const marker of 'FTPA') if (markers[1].includes(marker)) tip += '\n' + base.stickers[marker];
      output += `<span tabindex="0" class="term" data-tip="${esc(tip)}"><img class="rule-icon" src="${image}" alt="${esc(found[1])}"></span>`;
    } else output += esc(found[0]);
    offset = found.index + found[0].length;
  }
  return output + esc(source.slice(offset));
}

function render() {
  const query = $('#search').value.toLowerCase(), roster = $('#roster').value, kind = $('#kind').value, region = $('#region').value;
  const shown = units.filter(unit =>
    (roster === 'all' || (roster === 'current' ? unit.in_roster : roster === 'implemented' ? unit.implemented : roster === 'reference' ? !unit.implemented && !unit.custom : roster === 'custom' ? unit.custom : unit.implemented && !unit.in_roster)) &&
    (!kind || unit.kind === kind) && (!region || unit.deployment.toLowerCase().includes(region.toLowerCase())) &&
    [unit.name,unit.aliases,unit.id,unit.effects,unit.hover,unit.deployment].join(' ').toLowerCase().includes(query)
  ).sort((a,b) => direction * (sortKey === 'life' ? Number(a.life)-Number(b.life) : String(a[sortKey]).localeCompare(String(b[sortKey]))));
  $('#count').textContent = `${shown.length} of ${units.length} units`;
  $('#rows').innerHTML = shown.map(unit => {
    const field = (key, area=false) => area
      ? `<textarea class="edit" data-id="${esc(unit.id)}" data-field="${key}" aria-label="${key} for ${esc(unit.name)}">${esc(unit[key])}</textarea>`
      : `<input class="edit cell-input" ${key === 'life' ? 'type="number" min="1" step="1"' : 'type="text"'} data-id="${esc(unit.id)}" data-field="${key}" aria-label="${key} for ${esc(unit.name)}" value="${esc(unit[key])}">`;
    const effects = original(unit) && unit.effects === original(unit).effects
      ? unit.richEffects.map(text => `<p class="effect">${text}</p>`).join('')
      : `<div style="white-space:pre-line">${renderTokens(unit.effects)}</div>`;
    return `<tr><td><div class="unit">${unit.portrait ? `<img class="portrait" alt="" src="${unit.portrait}">` : `<div class="portrait initials" aria-hidden="true">${esc(unit.name[0] || '?')}</div>`}<div><div class="read name">${esc(unit.name)}</div>${field('name')}<div class="kind">${esc(unit.kind)}${unit.aliases ? '<br>Also: '+esc(unit.aliases) : ''}</div><span class="badge ${unit.implemented ? '' : 'alt'}">${unit.custom ? 'Custom draft' : unit.implemented ? 'Godot coded' : 'JS reference only'}</span>${unit.in_roster ? '<br><span class="badge">Current roster</span>' : ''}${changed(unit) ? '<div class="edited">Edited locally</div>' : ''}</div></div></td><td><div class="read life">${esc(unit.life)}</div>${field('life')}</td><td><div class="read deployment">${esc(unit.deployment)}</div>${field('deployment')}</td><td><div class="read">${!unit.implemented && !unit.custom ? '<div class="kind" style="margin-bottom:8px">Printed reference wording</div>' : ''}${effects}</div>${field('effects',true)}</td><td><details class="read"><summary>Rules & explanations</summary><div class="notes">${renderTokens(unit.hover)}</div></details>${field('hover',true)}</td></tr>`;
  }).join('') || '<tr><td colspan="5" class="empty">No units match these filters.</td></tr>';
  $('#source').textContent = `${units.length} units · ${units.filter(u=>u.implemented).length} Godot coded · ${units.filter(u=>!u.implemented&&!u.custom).length} reference only · ${units.filter(u=>u.custom).length} custom drafts`;
  hideTip();
}
for (const id of ['search','roster','kind','region']) $('#'+id).addEventListener('input', render);
document.querySelectorAll('[data-sort]').forEach(button => button.onclick = () => {direction = sortKey === button.dataset.sort ? -direction : 1; sortKey = button.dataset.sort; render();});
$('#edit').onclick = () => {editing = !editing; document.body.classList.toggle('editing',editing); $('#edit').textContent = editing ? 'Done editing' : 'Edit table'; render();};
$('#rows').addEventListener('input', event => {const input=event.target;if(!input.dataset.field)return;const unit=units.find(u=>u.id===input.dataset.id);unit[input.dataset.field]=input.dataset.field==='life'?Math.max(1,Number(input.value)||1):input.value;save();});

function download(name, text, type) {const url=URL.createObjectURL(new Blob([text],{type})),link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
$('#json').onclick = () => download('feral-kingdom-units.json',JSON.stringify({version:1,units:records()},null,2),'application/json');
$('#csv').onclick = () => {const keys=['name','aliases','kind','implemented','custom','life','deployment','effects','hover'];download('feral-kingdom-units.csv','\ufeff'+[keys,...records().map(unit=>keys.map(key=>unit[key]??''))].map(row=>row.map(value=>'"'+String(value).replaceAll('"','""')+'"').join(',')).join('\r\n'),'text/csv;charset=utf-8');};
$('#reset').onclick = () => {if(!confirm('Discard all local edits and custom drafts, and restore the game catalogue?'))return;units=structuredClone(base.units);try{localStorage.removeItem(storageKey);}catch{}render();$('#status').textContent='Restored the original game definitions.';};
$('#import').onclick = () => $('#file').click();
$('#file').onchange = async event => {try{const data=JSON.parse(await event.target.files[0].text());if(!Array.isArray(data.units))throw Error('No units array found.');const count=mergeRecords(data.units);save();render();$('#status').textContent=`Imported ${count} units, including custom drafts.`;}catch(error){$('#status').textContent='Could not import: '+error.message;}event.target.value='';};

const dialog = $('#add-dialog');
$('#add').onclick = () => {$('#add-form').reset();dialog.showModal();$('#new-name').focus();};
$('#cancel-add').onclick = () => dialog.close();
$('#add-form').onsubmit = event => {
  event.preventDefault();
  const unit = {id:'custom-'+(globalThis.crypto?.randomUUID?.() || Date.now().toString(36)+'-'+Math.random().toString(36).slice(2)),name:$('#new-name').value.trim(),kind:$('#new-kind').value,life:Number($('#new-life').value),deployment:$('#new-deployment').value.trim(),effects:$('#new-effects').value,hover:$('#new-hover').value,custom:true,implemented:false,in_roster:false,aliases:'',portrait:'',richEffects:[]};
  if(!unit.name || !Number.isInteger(unit.life) || unit.life<1)return;
  units.push(unit);save();dialog.close();
  $('#search').value=unit.name;$('#roster').value='all';$('#kind').value='';$('#region').value='';render();
  $('#status').textContent='Added '+unit.name+' as a custom draft. Export JSON to back it up. It has not been added to gameplay.';
};
let insertTarget = $('#new-effects');
for (const id of ['new-effects','new-hover']) $('#'+id).addEventListener('focus',event=>{insertTarget=event.target;});
$('#icon-palette').innerHTML = Object.entries(base.iconData).map(([key,image])=>`<button type="button" data-icon="${key}" title="Insert (${key==='move'?'walk':key})"><img class="rule-icon" src="${image}" alt="${key==='move'?'walk':key}"></button>`).join('');
$('#icon-palette').onclick = event => {const button=event.target.closest('[data-icon]');if(!button)return;const key=button.dataset.icon==='move'?'walk':button.dataset.icon;insertTarget.setRangeText('('+key+')',insertTarget.selectionStart,insertTarget.selectionEnd,'end');insertTarget.focus();};

const tooltip = $('#tooltip');
function hideTip() {tooltip.classList.remove('show');}
function showTip(element,x,y) {tooltip.textContent=element.dataset.tip;tooltip.classList.add('show');tooltip.style.left=Math.max(8,Math.min(x+16,innerWidth-tooltip.offsetWidth-12))+'px';tooltip.style.top=Math.max(8,Math.min(y+18,innerHeight-tooltip.offsetHeight-12))+'px';}
$('#rows').addEventListener('pointerover',event=>{const element=event.target.closest('[data-tip]');if(element)showTip(element,event.clientX,event.clientY);});
$('#rows').addEventListener('pointerout',event=>{if(event.target.closest('[data-tip]'))hideTip();});
$('#rows').addEventListener('focusin',event=>{const element=event.target.closest('[data-tip]');if(element){const rect=element.getBoundingClientRect();showTip(element,rect.left,rect.bottom);}});
$('#rows').addEventListener('focusout',hideTip);$('.table-wrap').addEventListener('scroll',hideTip);
document.addEventListener('keydown',event=>{if(event.key==='Escape')hideTip();});
render();
