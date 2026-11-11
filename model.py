import json, math
# Final Project model (KZT million unless noted). Builds on the Endterm model; changes are flagged CHG.
BASE = dict(
 clients=[20, 55, 110],            # average active subscribers
 integrations=[8, 22, 40],         # new API integrations per year
 ppc_checks=[2500, 7000, 14000],
 sub_price_m=0.150, integ_fee=1.2, ppc_price=2000, price_idx=0.05,    # CHG: prices indexed +5% a year from Year 2
 wage_idx=0.08,                                                       # CHG: salaries +8% a year from Year 2
 cost_mult=1.0, hiring_rule=False, tax=0.20, r=0.25, g=0.03,
 infra=[5.8, 6.8, 8.2], mkt=[10, 14, 18], office=[6, 8, 10], legal=[3, 3, 4],
 sec=dict(pentest=[1.5, 2.0, 2.5], bounty=[0.5, 0.5, 1.0], kms=[0.5, 0.6, 0.7], insur=[0.5, 0.9, 0.8]),  # CHG: risk mitigation in budget
 dev=dict(eng=43.2, audit=5.0, design=3.0, infra=1.2, keys=1.0, contingency=1.6),                      # CHG: 1.0 of the contingency moved to key management
 prelaunch=dict(legal=8.0, marketing=12.0, ops=5.0),
 funding=130.0,                                                       # CHG: ask 120 -> 130
)
def run(**kw):
    P = json.loads(json.dumps(BASE)); P.update(kw)
    Y = [1, 2, 3]
    cl = P['clients']
    pf = [(1 + P['price_idx']) ** (t - 1) for t in Y]
    wf = [(1 + P['wage_idx']) ** (t - 1) for t in Y]
    sub = [cl[i] * P['sub_price_m'] * 12 * pf[i] for i in range(3)]
    integ = [P['integrations'][i] * P['integ_fee'] * pf[i] for i in range(3)]
    ppc = [P['ppc_checks'][i] * P['ppc_price'] / 1e6 * pf[i] for i in range(3)]
    rev = [sub[i] + integ[i] + ppc[i] for i in range(3)]
    eng = [2, 3, 4]
    if P['hiring_rule']:
        sales = [max(1, math.ceil(cl[i] / 40 - 1e-9)) for i in range(3)]; supp = sales[:]
    else:
        sales = [1, 2, 3]; supp = [1, 2, 3]
    staff = [(eng[i] * 1.2 + sales[i] * 0.8 + supp[i] * 0.6 + 0.9) * 12 * wf[i] for i in range(3)]
    sec = [sum(v[i] for v in P['sec'].values()) for i in range(3)]
    other = [P['infra'][i] + P['mkt'][i] + P['office'][i] + P['legal'][i] + sec[i] for i in range(3)]
    opex = [(staff[i] + other[i]) * P['cost_mult'] for i in range(3)]
    dev = sum(P['dev'].values()); pre = sum(P['prelaunch'].values())
    amort = dev / 5
    ebitda = [rev[i] - opex[i] for i in range(3)]
    ebit = [ebitda[i] - amort for i in range(3)]
    # tax: Year 0 pre-launch costs are expensed (tax loss), losses carried forward
    loss = pre; tax = []; 
    for e in ebit:
        if e < 0: loss += -e; tax.append(0.0)
        else:
            use = min(loss, e); loss -= use; tax.append((e - use) * P['tax'])
    ni = [ebit[i] - tax[i] for i in range(3)]
    cfo = [-pre] + [ni[i] + amort for i in range(3)]
    cfi = [-dev, 0, 0, 0]
    fcf = [cfo[t] + cfi[t] for t in range(4)]
    cff = [P['funding'], 0, 0, 0]
    cash = []; c = 0
    for t in range(4): c += fcf[t] + cff[t]; cash.append(c)
    cum = []; s = 0
    for x in fcf: s += x; cum.append(s)
    r = P['r']; df = [1 / (1 + r) ** t for t in range(4)]
    pv = [fcf[t] * df[t] for t in range(4)]; npv3 = sum(pv)
    # normalised Year-3 FCF for terminal value: full tax, no loss carry-forward
    fcf3n = ebitda[2] - max(ebit[2], 0) * P['tax']
    tv = fcf3n * (1 + P['g']) / (r - P['g']); tv_pv = tv * df[3]
    npv_total = npv3 + tv_pv
    # payback (years); beyond Year 3 assume Year-4+ cash flow = normalised Year-3 FCF
    pb = None
    for k in range(1, 4):
        if cum[k] >= 0 and fcf[k] > 0: pb = (k - 1) + (-cum[k - 1]) / fcf[k]; break
    if pb is None and fcf3n > 0: pb = 3 + (-cum[3]) / fcf3n
    # IRR on 3-year flows, and with terminal value
    def irr(cfs):
        lo, hi = -0.99, 5.0
        f = lambda x: sum(cf / (1 + x) ** t for t, cf in enumerate(cfs))
        if f(lo) * f(hi) > 0: return None
        for _ in range(200):
            mid = (lo + hi) / 2
            if f(lo) * f(mid) <= 0: hi = mid
            else: lo = mid
        return (lo + hi) / 2
    irr3 = irr(fcf); irr_tv = irr(fcf[:3] + [fcf[3] + tv])
    arpc = [rev[i] / cl[i] for i in range(3)]
    be = [opex[i] / arpc[i] for i in range(3)]
    min_cash = min(cash); extra = max(0, -min_cash)
    # runway: months of Year-1 burn covered by cash at end of Year 0
    burn1 = -fcf[1] / 12
    runway = cash[0] / burn1 if burn1 > 0 else None
    return dict(P=P, rev=rev, sub=sub, integ=integ, ppc=ppc, staff=staff, sales=sales, supp=supp, sec=sec, other=other, opex=opex,
        ebitda=ebitda, amort=amort, ebit=ebit, tax=tax, ni=ni, cfo=cfo, cfi=cfi, cff=cff, fcf=fcf, cash=cash, cum=cum, df=df, pv=pv,
        npv3=npv3, fcf3n=fcf3n, tv=tv, tv_pv=tv_pv, npv_total=npv_total, pb=pb, irr3=irr3, irr_tv=irr_tv, arpc=arpc, be=be,
        min_cash=min_cash, extra=extra, runway=runway, dev=dev, pre=pre, init=dev + pre, reserve=P['funding'] - dev - pre,
        staff_share=[staff[i] * P['cost_mult'] / opex[i] for i in range(3)], infra_share=[P['infra'][i] / opex[i] for i in range(3)])
base = run()
sc = {
 'S0 Base case': base,
 'S1 Clients -30%, hiring unchanged': run(clients=[c * 0.7 for c in BASE['clients']], integrations=[n * 0.7 for n in BASE['integrations']], ppc_checks=[n * 0.7 for n in BASE['ppc_checks']]),
 'S2 Clients -30%, hiring follows clients': run(clients=[c * 0.7 for c in BASE['clients']], integrations=[n * 0.7 for n in BASE['integrations']], ppc_checks=[n * 0.7 for n in BASE['ppc_checks']], hiring_rule=True),
 'S3 Operating costs +10%': run(cost_mult=1.10),
 'S4 Slower ramp (6-month delay)': run(clients=[10, 35, 80], integrations=[4, 14, 30], ppc_checks=[1200, 4500, 10500], hiring_rule=True),
 'S5 Clients -30% and costs +10%': run(clients=[c * 0.7 for c in BASE['clients']], integrations=[n * 0.7 for n in BASE['integrations']], ppc_checks=[n * 0.7 for n in BASE['ppc_checks']], hiring_rule=True, cost_mult=1.10),
}
# discount-rate range check on base case
dr = {f'{int(r*100)}%': round(run(r=r)['npv3'], 1) for r in (0.20, 0.25, 0.30)}
dr_tot = {f'{int(r*100)}%': round(run(r=r)['npv_total'], 1) for r in (0.20, 0.25, 0.30)}
# Extension Years 4-5 only for the exit valuation (revenue = clients x ARPC, ARPC indexed +5%)
cl45 = [150, 190]; arpc3 = base['arpc'][2]
rev45 = [cl45[0] * arpc3 * 1.05, cl45[1] * arpc3 * 1.05 ** 2]
exit_mult = 2.0
ev5 = exit_mult * rev45[1]
hurdle = 1.25 ** 5
share_needed = base['P']['funding'] * hurdle / ev5
ask_share = math.ceil(share_needed * 20) / 20       # round up to 5 %
post = base['P']['funding'] / ask_share; pre = post - base['P']['funding']
moic = ask_share * ev5 / base['P']['funding']; inv_irr = moic ** (1 / 5) - 1
out = dict(base=base, scenarios=sc, dr=dr, dr_tot=dr_tot, rev45=rev45, ev5=ev5, share_needed=share_needed, ask_share=ask_share, post=post, pre=pre, moic=moic, inv_irr=inv_irr, exit_mult=exit_mult)
json.dump(out, open('model2.json', 'w'), indent=1, default=lambda o: o)
f = lambda L: [round(x, 1) if isinstance(x, (int, float)) else x for x in L]
b = base
for k in ['rev', 'staff', 'sec', 'opex', 'ebitda', 'ebit', 'tax', 'ni', 'cfo', 'fcf', 'cash', 'cum', 'pv', 'be', 'arpc', 'staff_share', 'infra_share']: print(k, f(b[k]) if k not in ('staff_share', 'infra_share', 'arpc') else [round(x, 3) for x in b[k]])
print('npv3', round(b['npv3'], 1), 'fcf3n', round(b['fcf3n'], 1), 'tv', round(b['tv'], 1), 'tv_pv', round(b['tv_pv'], 1), 'npv_total', round(b['npv_total'], 1), 'pb', round(b['pb'], 2), 'irr3', b['irr3'], 'irr_tv', b['irr_tv'])
print('min_cash', round(b['min_cash'], 1), 'runway months', round(b['runway'], 1), 'init', b['init'], 'reserve', b['reserve'], 'dr', dr, dr_tot)
print('rev45', f(rev45), 'ev5', round(ev5, 1), 'share_needed', round(share_needed, 3), 'ask', ask_share, 'post', round(post, 1), 'pre', round(pre, 1), 'moic', round(moic, 2), 'irr', round(inv_irr, 3))
for k, v in sc.items(): print(k, '| NPV3', round(v['npv3'], 1), '| NPVtot', round(v['npv_total'], 1), '| minCash', round(v['min_cash'], 1), '| extra', round(v['extra'], 1), '| pb', None if v['pb'] is None else round(v['pb'], 2), '| fcf', f(v['fcf']), '| opex', f(v['opex']), '| rev', f(v['rev']))

# ---- extras for the report ----
gas = 76365; eth_kzt = gas * 5e-9 * 3000 * 500           # illustrative: 5 gwei, 3,000 USD/ETH, 500 KZT/USD
docs3 = 60000
extras = dict(gas=gas, eth_kzt_per_record=eth_kzt, eth_kzt_year3=eth_kzt * docs3 / 1e6,
              tps_y3=docs3 / (365 * 24 * 3600))
inv = []
fund = base['P']['funding']
def irr_of(m): return m ** (1 / 5) - 1
for lab, mult, scale in [('Base case, exit at 2.0x revenue', 2.0, 1.0), ('Base case, exit at 1.0x revenue', 1.0, 1.0), ('Base case, exit at 3.0x revenue', 3.0, 1.0), ('Clients -30%, exit at 2.0x revenue', 2.0, 0.7)]:
    ev = mult * rev45[1] * scale; val = ask_share * ev; m = val / fund
    inv.append(dict(label=lab, ev=ev, stake=val, moic=m, irr=irr_of(m)))
out['extras'] = extras; out['inv'] = inv
out['cl45'] = cl45
json.dump(out, open('model2.json', 'w'), indent=1, default=lambda o: o)
print(extras); [print(i['label'], round(i['ev'],1), round(i['stake'],1), round(i['moic'],2), round(i['irr'],3)) for i in inv]
