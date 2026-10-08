import json, os, shutil, copy, sys
ROOT = sys.argv[1]   # .../mortgage_mi.Report/definition
PG = os.path.join(ROOT, 'pages')
def L(v): return {"expr": {"Literal": {"Value": v}}}
def S(c): return {"solid": {"color": L("'%s'" % c)}}
def num(n): return L("%sD" % n)
def boo(b): return L("true" if b else "false")
def txt(s): return L("'%s'" % s.replace("'", "''"))
NAVY = "#12263F"; GREY = "#5B6678"; INK = "#1F2A3C"

def load(p): return json.load(open(p, encoding='utf-8'))
def save(p, d):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(d, f, indent=2, ensure_ascii=True); f.write("\n")

# remove smoke test page
smoke = '3a311e080fbea1f3cb85'
if os.path.isdir(os.path.join(PG, smoke)):
    shutil.rmtree(os.path.join(PG, smoke))
pm = load(os.path.join(PG, 'pages.json'))
pm['pageOrder'] = [p for p in pm['pageOrder'] if p != smoke]
# page order: overview, risk, data quality
order = ['6b45e7b70ab2ab8ab26a', 'a65551e33611701c9bed', '6f3cbfaed013b000cb8e']
pm['pageOrder'] = order
pm['activePageName'] = order[0]
save(os.path.join(PG, 'pages.json'), pm)

for pid in order:
    p = os.path.join(PG, pid, 'page.json'); d = load(p)
    d['width'] = 1280; d['height'] = 720; d['displayOption'] = 'FitToPage'
    save(p, d)

def vpath(pid, vid): return os.path.join(PG, pid, 'visuals', vid, 'visual.json')

def style(v, title=None, bg=False, pad=None, title_size=13):
    vis = v['visual']
    vco = vis.setdefault('visualContainerObjects', {})
    if pad is None and bg:
        pad = {"left": 12, "top": 8, "right": 12, "bottom": 10}
    if title is not None:
        vco['subTitle'] = [{"properties": {"show": boo(False)}}]
        vco['title'] = [{"properties": {"show": boo(True), "text": txt(title), "fontSize": num(title_size),
                                        "bold": boo(True), "fontColor": S(NAVY)}}]
    if bg:
        vco['background'] = [{"properties": {"show": boo(True), "color": S("#FFFFFF"), "transparency": num(0)}}]
        vco['border'] = [{"properties": {"show": boo(True), "color": S("#D5DCE8"), "radius": num(8)}}]
    if pad:
        vco['padding'] = [{"properties": {k: num(x) for k, x in pad.items()}}]

def place(v, x, y, w, h, z):
    pos = v['position']; pos.update({"x": x, "y": y, "width": w, "height": h, "z": z, "tabOrder": z})

def rename(v, qref, name):
    for role in v['visual']['query']['queryState'].values():
        for pr in role['projections']:
            if pr['queryRef'] == qref: pr['displayName'] = name; return
    raise SystemExit("no projection " + qref)

def card(v, label, size=26, label_size=11, show_label=True):
    objs = v['visual'].setdefault('objects', {})
    objs['value'] = [{"properties": {"fontSize": num(size), "fontColor": S(NAVY), "labelDisplayUnits": num(1)}}]
    objs['outline'] = [{"properties": {"show": boo(False)}}]
    objs['borderCustom'] = [{"properties": {"show": boo(False)}}]
    objs['label'] = [{"properties": {"show": boo(show_label), "fontSize": num(label_size), "fontColor": S(GREY)}}]
    if label:
        qref = list(v['visual']['query']['queryState']['Data']['projections'])[0]['queryRef']
        rename(v, qref, label)

def totals_off(v):
    v['visual'].setdefault('objects', {})['total'] = [{"properties": {"totals": boo(False)}}]

def header_text(text):
    return {"properties": {"paragraphs": [{"textRuns": [{"value": text,
            "textStyle": {"fontWeight": "bold", "fontSize": "20pt", "color": "#FFFFFF"}}]}]}}

def header(v, text):
    v['visual']['objects']['general'] = [header_text(text)]
    vco = v['visual'].setdefault('visualContainerObjects', {})
    vco['background'] = [{"properties": {"show": boo(True), "color": S(NAVY), "transparency": num(0)}}]
    vco['padding'] = [{"properties": {"left": num(24), "top": num(14), "right": num(0), "bottom": num(0)}}]
    vco['border'] = [{"properties": {"show": boo(False)}}]

def band_slicer(v):
    place(v, 1020, 12, 236, 40, 50)
    v['visual'].setdefault('objects', {})['header'] = [{"properties": {"show": boo(False)}}]
    vco = v['visual'].setdefault('visualContainerObjects', {})
    vco['background'] = [{"properties": {"show": boo(True), "color": S("#FFFFFF"), "transparency": num(0)}}]
    vco['border'] = [{"properties": {"show": boo(True), "color": S("#FFFFFF"), "radius": num(4)}}]

# Page 1: executive overview
P1 = '6b45e7b70ab2ab8ab26a'
def edit(pid, vid, fn):
    p = vpath(pid, vid); d = load(p); fn(d); save(p, d)

def p1_header(d): place(d, 0, 0, 1280, 64, 0); header(d, "Mortgage arrears: executive overview")
edit(P1, 'ef5d2dd1596542de829b', p1_header)
edit(P1, 'e694ea1bdfb4f7401955', band_slicer)
kp = [('c16db936854dca2f9587', 24, "Arrears accounts"), ('a0e4fbad4751b0e74833', 273, "Arrears rate (accounts)"),
      ('47919148d2a0aadb503d', 522, "Arrears rate (balance)"), ('72007c663c934b5b8f30', 771, "Outstanding (EUR bn)"),
      ('87d7f77a8c34bb4325b0', 1020, "Change vs previous quarter")]
for i, (vid, x, lab) in enumerate(kp):
    def f(d, x=x, lab=lab, i=i):
        place(d, x, 80, 236, 96, 1 + i); card(d, lab); style(d, bg=True, pad={"left": 14, "top": 8, "right": 8, "bottom": 8})
    edit(P1, vid, f)
def note(d):
    place(d, 24, 184, 1232, 62, 6); card(d, "Completeness check", size=14, label_size=10)
    style(d, bg=True, pad={"left": 16, "top": 6, "right": 8, "bottom": 6})
edit(P1, 'a35d597364319c2be667', note)
def f_bar(d): place(d, 24, 256, 520, 206, 7); style(d, "Arrears rate by segment (accounts)", bg=True)
def f_line(d): place(d, 556, 256, 700, 206, 8); style(d, "Market arrears rate over time (quarters where all 4 segments report)", bg=True)
def f_tab(d): place(d, 24, 474, 1232, 230, 9); style(d, "Segment summary", bg=True)
edit(P1, '6ae2d073de58d8cf26f4', f_bar); edit(P1, 'dd42a626fdd422279ec4', f_line); edit(P1, 'd7e97853508eea14f00e', f_tab)

# Page 2: risk and arrears
P2 = 'a65551e33611701c9bed'
# new header textbox cloned from page 1
src = load(vpath(P1, 'ef5d2dd1596542de829b')); newid = 'b7c2e1a94d3f5a60c811'
src['name'] = newid; header(src, "Risk and arrears by segment"); place(src, 0, 0, 1280, 64, 0)
os.makedirs(os.path.dirname(vpath(P2, newid)), exist_ok=True); save(vpath(P2, newid), src)
edit(P2, '5ca27501579126e39e6b', band_slicer)
def hr(d): place(d, 24, 80, 300, 80, 1); card(d, "Highest risk segment", size=22); style(d, bg=True, pad={"left": 14, "top": 8, "right": 8, "bottom": 8})
edit(P2, '8c2888a4c9820cc0903b', hr)
def seg(d):
    place(d, 336, 80, 920, 80, 2); style(d, "Filter by segment", bg=True, title_size=11, pad={"left": 16, "top": 12, "right": 16, "bottom": 12})
    d['visual']['objects']['general'] = [{"properties": {"orientation": num(1)}}]
edit(P2, '4476f62e0fb7020decd2', seg)
def stk(d): place(d, 24, 172, 740, 260, 3); style(d, "Accounts in arrears by age", bg=True)
def ln(d): place(d, 776, 172, 480, 260, 4); style(d, "Arrears rate over time (accounts)", bg=True)
def ob(d): place(d, 24, 444, 400, 260, 5); style(d, "Over 180 days share by segment", bg=True)
def tb(d): place(d, 436, 444, 820, 260, 6); style(d, "Segment risk table", bg=True)
edit(P2, '076a1259406dd71caf6c', stk); edit(P2, '5254f72232ab55c77197', ln)
edit(P2, 'cedf2fc10cec62056e13', ob); edit(P2, '8037659020b3edd3eaef', tb)

# Page 3: data quality
P3 = '6f3cbfaed013b000cb8e'
def p3h(d): place(d, 0, 0, 1280, 64, 0); header(d, "Data quality: what was tested and what was found")
edit(P3, '637c16befb6017f8ccb2', p3h)
cards3 = [('4c9f198f10eb945d3e8e', 24, "Rules run"), ('96815b8624ad813ed8e5', 231, "Rules passed"),
          ('8a15daa9b42c942df2b0', 438, "Rules with warning"), ('6f9e82d07de1495d5742', 645, "Rules info only"),
          ('45b226ca20981f5edd33', 852, "Rules failed"), ('5ed5f6c58170964d7b9d', 1059, "Reconciliation steps matched")]
for i, (vid, x, lab) in enumerate(cards3):
    def f(d, x=x, lab=lab, i=i):
        place(d, x, 80, 194, 88, 1 + i); card(d, lab, size=26); style(d, bg=True, pad={"left": 14, "top": 8, "right": 8, "bottom": 8})
    edit(P3, vid, f)
def rules(d):
    place(d, 24, 180, 760, 260, 7); style(d, "Results by rule", bg=True); totals_off(d)
    rename(d, 'dq_check_result.rows_tested', "Rows tested"); rename(d, 'dq_check_result.rows_failed', "Rows failed")
def dimbar(d): place(d, 796, 180, 460, 260, 8); style(d, "Rules run by dimension and status", bg=True)
def issues(d):
    place(d, 24, 452, 720, 252, 9); style(d, "Issue log", bg=True); totals_off(d)
    rename(d, 'Sum(dq_issue_log.rows_affected)', "Rows affected")
def recon(d):
    place(d, 756, 452, 300, 252, 10); style(d, "Reconciliation by check", bg=True); totals_off(d)
    rename(d, 'dq_reconciliation.check_name', "Check")
def tnote(d):
    place(d, 1068, 452, 188, 252, 11)
    d['visual']['objects']['general'] = [{"properties": {"paragraphs": [{"textRuns": [{"value":
      "How to read this page: checks run in SQL (sql/09 and sql/10). Warnings are reviewed and documented in the issue log. Error-level failures stop the pipeline, so failures shown here are 0 by design.",
      "textStyle": {"fontSize": "10pt", "color": GREY}}]}]}}]
    style(d, bg=True, pad={"left": 12, "top": 10, "right": 10, "bottom": 10})
    d['visual']['visualContainerObjects']['background'][0]['properties']['show'] = boo(True)
edit(P3, 'a53f078be7598eddd8d6', rules); edit(P3, 'dfee9ad8c22c2978bd96', dimbar)
edit(P3, 'a6f5304f2805885e14ae', issues); edit(P3, '7a5a808238d1d2eb9016', recon); edit(P3, '3da2ffaf65bbb6ad4bd7', tnote)
print("layout applied")

# Trend charts: sort by quarter, oldest first (a measure sort scrambles the time axis)
def sort_by_quarter(d):
    q = d['visual']['query']
    q['sortDefinition'] = {"sort": [{"field": {"Column": {"Expression": {"SourceRef": {"Entity": "dim_date"}},
                                                           "Property": "quarter_label"}},
                                     "direction": "Ascending"}]}
    d['visual'].setdefault('objects', {})['categoryAxis'] = [{"properties": {"preferredCategoryWidth": num(8)}}]
edit(P1, 'dd42a626fdd422279ec4', sort_by_quarter)
edit(P2, '5254f72232ab55c77197', sort_by_quarter)
print("sort applied")
