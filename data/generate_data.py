"""
Generates the fictional source-system extracts used by this project.

    python data/generate_data.py          # rewrites data/batch_1 and data/batch_2

Four source systems, laid out exactly the way they are uploaded to the Snowflake stage:

    <batch>/crm/branch/       CSV   branches
    <batch>/crm/advisor/      CSV   relationship managers
    <batch>/crm/client/       CSV   clients (full extract in batch_1, changed rows only in batch_2)
    <batch>/crm/meeting/      NDJSON client-advisor meetings (one JSON object per line)
    <batch>/core/account/     CSV   accounts
    <batch>/core/account_holder/ CSV  account <-> client ownership (joint accounts)
    <batch>/core/application/ CSV   account-opening workflow events
    <batch>/oms/transaction/  CSV   trades + cash movements, one file per week
    <batch>/mkt/security/     JSON  security master as a JSON array (nested listings)
    <batch>/mkt/price/        CSV   daily OHLC prices, one file per week

batch_1 = 03-Aug-2026 .. 25-Sep-2026, batch_2 = 28-Sep-2026 .. 02-Oct-2026 (incremental day).
Deliberate data defects (so the pipeline has something to handle):
  * one trade is re-sent in the next week's file (duplicate txn_id)
  * one trade has side written as 'buy ' (case / whitespace)
  * one trade references ticker 'XYZLTD' that is not in the security master (unknown member)
"""
import csv, json, os, random, shutil
import datetime as dt

random.seed(7)
ROOT = os.path.dirname(os.path.abspath(__file__))

B1_START, B1_END = dt.date(2026, 8, 3), dt.date(2026, 9, 25)
B2_START, B2_END = dt.date(2026, 9, 28), dt.date(2026, 10, 2)


def bdays(a, b):
    d, out = a, []
    while d <= b:
        if d.weekday() < 5:
            out.append(d)
        d += dt.timedelta(days=1)
    return out


def next_bday(d):
    d += dt.timedelta(days=1)
    while d.weekday() >= 5:
        d += dt.timedelta(days=1)
    return d


def write_csv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def ts(d, h=None, m=None):
    return dt.datetime.combine(d, dt.time(h if h is not None else random.randint(9, 15),
                                          m if m is not None else random.randint(0, 59),
                                          random.randint(0, 59)))


for b in ("batch_1", "batch_2"):
    shutil.rmtree(os.path.join(ROOT, b), ignore_errors=True)

# ------------------------------------------------------------------ CRM: branches / advisors
branches = [
    (10, "Mumbai BKC", "Mumbai", "WEST", "2012-04-01"),
    (20, "Bangalore Indiranagar", "Bangalore", "SOUTH", "2014-07-15"),
    (30, "Delhi Connaught Place", "Delhi", "NORTH", "2013-01-10"),
    (40, "Chennai T Nagar", "Chennai", "SOUTH", "2016-09-01"),
]
write_csv(f"{ROOT}/batch_1/crm/branch/crm_branch_20260801.csv",
          ["branch_id", "branch_name", "city", "region", "opened_date"], branches)

adv_names = [("Neha", "Kulkarni"), ("Vikram", "Joshi"), ("Priya", "Raman"), ("Arjun", "Hegde"),
             ("Sanjay", "Malhotra"), ("Pooja", "Bansal"), ("Lakshmi", "Iyer"), ("Karthik", "Subramanian")]
designations = ["RELATIONSHIP MANAGER", "SENIOR RELATIONSHIP MANAGER", "WEALTH MANAGER"]
advisors = []
for i, (fn, ln) in enumerate(adv_names):
    br = branches[i // 2]
    advisors.append((201 + i, fn, ln, designations[i % 3], br[0],
                     f"{fn.lower()}.{ln.lower()}@wm-example.in",
                     str(dt.date(2015 + i % 6, 1 + i, 1))))
write_csv(f"{ROOT}/batch_1/crm/advisor/crm_advisor_20260801.csv",
          ["advisor_id", "first_name", "last_name", "designation", "branch_id", "email", "joined_date"], advisors)
adv_by_city = {}
for a in advisors:
    city = next(b[2] for b in branches if b[0] == a[4])
    adv_by_city.setdefault(city, []).append(a[0])

# ------------------------------------------------------------------ CRM: clients
first = ["Aarav", "Diya", "Rohan", "Ananya", "Kabir", "Isha", "Vihaan", "Meera", "Aditya", "Sneha",
         "Arnav", "Kavya", "Reyansh", "Tara", "Ishaan", "Riya", "Dhruv", "Nisha", "Yash", "Anika"]
last = ["Shah", "Iyer", "Mehta", "Rao", "Nair", "Kapoor", "Reddy", "Gupta", "Menon", "Desai",
        "Pillai", "Chopra", "Bhat", "Saxena", "Verma", "Agarwal", "Sinha", "Patil", "Ghosh", "Dutta"]
cities = ["Mumbai", "Bangalore", "Delhi", "Chennai"]
segments = ["RETAIL", "HNI", "UHNI"]
risks = ["CONSERVATIVE", "MODERATE", "AGGRESSIVE"]


def fake_pan():
    L = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    return "".join(random.choice(L) for _ in range(3)) + "P" + random.choice(L) + \
        f"{random.randint(1000, 9999)}" + random.choice(L)


clients = {}
NEW_CLIENT_IDS = [1037, 1038, 1039, 1040]          # onboarded during batch_1 via the application workflow
for i in range(40):
    cid = 1001 + i
    fn, ln = first[i % 20], last[(i * 7) % 20]
    city = cities[i % 4]
    onboarded = dt.date(2016 + i % 9, 1 + i % 12, 1 + i % 27) if cid not in NEW_CLIENT_IDS \
        else dt.date(2026, 8, 3) + dt.timedelta(days=3 * (cid - 1037))
    clients[cid] = dict(
        client_id=cid, first_name=fn, last_name=ln,
        email=f"{fn.lower()}.{ln.lower()}{cid}@mail-example.in",
        phone=f"+91-9{random.randint(100000000, 999999999)}",
        pan=fake_pan(),
        date_of_birth=str(dt.date(1955 + i % 40, 1 + i % 12, 1 + i % 28)),
        city=city, segment=segments[(i * 5) % 3], risk_profile=risks[(i * 11) % 3],
        primary_advisor_id=random.choice(adv_by_city[city]),
        onboarded_date=str(onboarded),
        updated_at=str(dt.datetime.combine(onboarded if onboarded > dt.date(2026, 7, 31) else dt.date(2026, 7, 31),
                                           dt.time(18, 0))))
CL_COLS = ["client_id", "first_name", "last_name", "email", "phone", "pan", "date_of_birth", "city",
           "segment", "risk_profile", "primary_advisor_id", "onboarded_date", "updated_at"]
# deliberately messy casing in source for a couple of rows
clients[1005]["city"] = " chennai "
clients[1012]["risk_profile"] = "moderate"
write_csv(f"{ROOT}/batch_1/crm/client/crm_client_20260925.csv", CL_COLS,
          [[c[k] for k in CL_COLS] for c in clients.values()])

# ------------------------------------------------------------------ CORE: accounts + holders + applications
acct_types = ["BROKERAGE", "RETIREMENT", "ADVISORY", "PMS"]
accounts, holders, app_events = [], [], []
branch_by_city = {b[2]: b[0] for b in branches}
aid = 50000
for cid, c in clients.items():
    n = 1 if cid in NEW_CLIENT_IDS else random.choice([1, 1, 2])
    for k in range(n):
        aid += 1
        city = c["city"].strip().title()
        opened = dt.date.fromisoformat(c["onboarded_date"]) + dt.timedelta(days=0 if k == 0 else 400)
        if cid in NEW_CLIENT_IDS:
            opened = dt.date.fromisoformat(c["onboarded_date"]) + dt.timedelta(days=6)
            while opened.weekday() >= 5:
                opened += dt.timedelta(days=1)
        status, closed = "ACTIVE", ""
        if aid in (50007, 50021):
            status, closed = "CLOSED", "2025-12-31"
        accounts.append([aid, cid, random.choice(acct_types), "INR", status, str(opened), closed,
                         branch_by_city[city], f"{max(opened, dt.date(2026, 7, 31))} 18:00:00"])
        holders.append([aid, cid, "PRIMARY", 100.00])

# joint accounts: second holder, split 60/40
for acc in random.sample([a for a in accounts if a[4] == "ACTIVE"], 7):
    other = random.choice([c for c in clients if c != acc[1]])
    for h in holders:
        if h[0] == acc[0]:
            h[3] = 60.00
    holders.append([acc[0], other, "JOINT", 40.00])

# application workflow for the 4 new clients (all complete in batch_1)
app_id = 7000
for cid in NEW_CLIENT_IDS:
    app_id += 1
    applied = dt.date.fromisoformat(clients[cid]["onboarded_date"])
    acc = next(a for a in accounts if a[1] == cid)
    app_events += [
        [app_id, cid, acc[2], "", "APPLIED", ts(applied)],
        [app_id, cid, acc[2], "", "KYC_SUBMITTED", ts(applied + dt.timedelta(days=1))],
        [app_id, cid, acc[2], "", "KYC_APPROVED", ts(applied + dt.timedelta(days=4))],
        [app_id, cid, acc[2], acc[0], "ACCOUNT_OPENED", ts(dt.date.fromisoformat(acc[5]))],
    ]
# existing clients applying for an extra account: 2 in progress (finish in batch_2), 1 stuck, 2 rejected
pending = []
for j, (cid, last_stage) in enumerate([(1003, "KYC_SUBMITTED"), (1016, "KYC_APPROVED"),
                                       (1022, "APPLIED"), (1009, "REJECTED"), (1030, "REJECTED")]):
    app_id += 1
    applied = dt.date(2026, 9, 1) + dt.timedelta(days=4 * j)
    atype = random.choice(acct_types)
    app_events.append([app_id, cid, atype, "", "APPLIED", ts(applied)])
    if last_stage in ("KYC_SUBMITTED", "KYC_APPROVED", "REJECTED"):
        app_events.append([app_id, cid, atype, "", "KYC_SUBMITTED", ts(applied + dt.timedelta(days=2))])
    if last_stage == "KYC_APPROVED":
        app_events.append([app_id, cid, atype, "", "KYC_APPROVED", ts(applied + dt.timedelta(days=5))])
    if last_stage == "REJECTED":
        app_events.append([app_id, cid, atype, "", "REJECTED", ts(applied + dt.timedelta(days=6))])
    if cid in (1003, 1016):
        pending.append((app_id, cid, atype, last_stage))

AC_COLS = ["account_id", "client_id", "account_type", "currency", "status", "opened_date", "closed_date",
           "branch_id", "updated_at"]
write_csv(f"{ROOT}/batch_1/core/account/core_account_20260925.csv", AC_COLS, accounts)
write_csv(f"{ROOT}/batch_1/core/account_holder/core_account_holder_20260925.csv",
          ["account_id", "client_id", "holder_role", "ownership_pct"], holders)
APP_COLS = ["application_id", "client_id", "requested_account_type", "account_id", "event_type", "event_ts"]
write_csv(f"{ROOT}/batch_1/core/application/core_application_events_20260925.csv", APP_COLS, app_events)

# ------------------------------------------------------------------ MKT: securities (JSON) + prices
secs = [
    ("INFY", "Infosys Ltd", "EQUITY", "IT", 1850.0, 5), ("TCS", "Tata Consultancy Services", "EQUITY", "IT", 4100.0, 1),
    ("WIPRO", "Wipro Ltd", "EQUITY", "IT", 540.0, 2), ("HDFCBANK", "HDFC Bank Ltd", "EQUITY", "FINANCIALS", 1650.0, 1),
    ("ICICIBANK", "ICICI Bank Ltd", "EQUITY", "FINANCIALS", 1250.0, 2), ("RELIANCE", "Reliance Industries Ltd", "EQUITY", "ENERGY", 2950.0, 10),
    ("ITC", "ITC Ltd", "EQUITY", "FMCG", 470.0, 1), ("HINDUNILVR", "Hindustan Unilever Ltd", "EQUITY", "FMCG", 2600.0, 1),
    ("SUNPHARMA", "Sun Pharmaceutical Industries", "EQUITY", "HEALTHCARE", 1700.0, 1), ("LT", "Larsen & Toubro Ltd", "EQUITY", "INDUSTRIALS", 3600.0, 2),
    ("NIFTYBEES", "Nifty 50 ETF", "ETF", "INDEX", 265.0, 1), ("BANKBEES", "Bank Nifty ETF", "ETF", "INDEX", 520.0, 1),
    ("GOLDBEES", "Gold ETF", "ETF", "COMMODITY", 62.0, 1), ("GSEC2033", "GOI 7.18% 2033", "BOND", "SOVEREIGN", 101.5, 100),
    ("LIQUIDBEES", "Liquid ETF", "ETF", "CASH_EQUIVALENT", 1000.0, 1),
]
sec_json = []
for i, (t, n, ac, sector, px, fv) in enumerate(secs):
    sec_json.append({
        "ticker": t, "isin": f"INE{900 + i:03d}X01{i:02d}9", "name": n, "asset_class": ac, "sector": sector,
        "attributes": {"face_value": fv, "currency": "INR", "lot_size": 1},
        "listings": [{"exchange": "NSE", "symbol": t},
                     {"exchange": "BSE", "symbol": str(500100 + i * 7)}],
    })
os.makedirs(f"{ROOT}/batch_1/mkt/security", exist_ok=True)
with open(f"{ROOT}/batch_1/mkt/security/mkt_security_master_20260801.json", "w") as f:
    json.dump(sec_json, f, indent=2)

last_px = {s[0]: s[4] for s in secs}
prices = {}


def price_files(days, batch):
    weeks = {}
    for d in days:
        weeks.setdefault(d - dt.timedelta(days=d.weekday()), []).append(d)
    for wk, ds in weeks.items():
        rows = []
        for d in ds:
            for s in secs:
                t = s[0]
                vol = 0.003 if s[2] in ("BOND", "ETF") and s[3] in ("SOVEREIGN", "CASH_EQUIVALENT") else 0.013
                o = last_px[t]
                c = round(o * (1 + random.gauss(0.0006, vol)), 2)
                hi, lo = round(max(o, c) * (1 + abs(random.gauss(0, vol / 2))), 2), round(min(o, c) * (1 - abs(random.gauss(0, vol / 2))), 2)
                last_px[t] = c
                prices[(t, d)] = c
                rows.append([t, d, o, hi, lo, c, random.randint(20000, 900000)])
        write_csv(f"{ROOT}/{batch}/mkt/price/mkt_price_week_{wk:%Y%m%d}.csv",
                  ["ticker", "price_date", "open", "high", "low", "close", "volume"], rows)


price_files(bdays(B1_START, B1_END), "batch_1")
price_files(bdays(B2_START, B2_END), "batch_2")

# ------------------------------------------------------------------ OMS: transactions
TX_COLS = ["txn_id", "account_id", "txn_type", "ticker", "quantity", "price", "amount", "fees",
           "channel", "order_type", "txn_ts", "settle_date", "status"]
holdings = {}
txn_id = [900000]


def new_txn(acc, d, ttype, ticker="", qty="", price="", amount="", channel=None, order_type=""):
    txn_id[0] += 1
    fees = round(qty * price * 0.0003, 2) if ttype in ("BUY", "SELL") else 0
    return [txn_id[0], acc, ttype, ticker, qty, price, amount, fees,
            channel or random.choice(["ONLINE", "ONLINE", "BRANCH", "ADVISOR_DESK"]),
            order_type, ts(d), next_bday(d), "SETTLED"]


def gen_txns(days, active_accounts, batch, opened_on=None):
    opened_on = opened_on or {}
    weeks = {}
    for d in days:
        out = weeks.setdefault(d - dt.timedelta(days=d.weekday()), [])
        for acc in active_accounts:
            if acc in opened_on and d < opened_on[acc]:
                continue
            if acc in opened_on and d == opened_on[acc]:          # first funding of a new account
                out.append(new_txn(acc, d, "DEPOSIT", amount=random.choice([500000, 1000000, 2500000])))
                continue
            if random.random() < 0.25:
                s = random.choice(secs)
                t, px = s[0], prices[(s[0], d)]
                h = holdings.get((acc, t), 0)
                side = "SELL" if h >= 10 and random.random() < 0.35 else "BUY"
                q = random.randint(1, h // 2) if side == "SELL" else random.randint(5, 80)
                holdings[(acc, t)] = h + (q if side == "BUY" else -q)
                out.append(new_txn(acc, d, side, t, q, round(px * random.uniform(0.997, 1.003), 2),
                                   order_type=random.choice(["MARKET", "MARKET", "LIMIT"])))
            if random.random() < 0.006:
                out.append(new_txn(acc, d, "WITHDRAWAL", amount=random.choice([25000, 50000, 100000])))
        # dividends on Fridays for anyone holding ITC / INFY
        if d.weekday() == 4 and d.day <= 7:
            for (acc, t), q in list(holdings.items()):
                if t in ("ITC", "INFY") and q > 0:
                    out.append(new_txn(acc, d, "DIVIDEND", t, amount=round(q * 6.5, 2), channel="ONLINE"))
        # month-end advisory fee
        if next_bday(d).month != d.month:
            for acc in active_accounts:
                if acc_type[acc] in ("ADVISORY", "PMS") and (acc not in opened_on or opened_on[acc] <= d):
                    out.append(new_txn(acc, d, "FEE", amount=2500 if acc_type[acc] == "ADVISORY" else 7500,
                                       channel="BRANCH"))
    return weeks


acc_type = {a[0]: a[2] for a in accounts}
active = [a[0] for a in accounts if a[4] == "ACTIVE"]
new_acc_open = {a[0]: dt.date.fromisoformat(a[5]) for a in accounts if a[1] in NEW_CLIENT_IDS}
weeks1 = gen_txns(bdays(B1_START, B1_END), active, "batch_1", new_acc_open)
wk_keys = sorted(weeks1)
# defects
weeks1[wk_keys[3]].append(list(weeks1[wk_keys[2]][4]))                 # duplicate re-sent next week
messy = next(r for r in weeks1[wk_keys[1]] if r[2] == "BUY")
messy[2] = "buy "                                                       # dirty side value
bad = new_txn(active[0], wk_keys[5], "BUY", "XYZLTD", 10, 99.5, order_type="MARKET")
weeks1[wk_keys[5]].append(bad)                                          # ticker missing from master
for wk, rows in weeks1.items():
    write_csv(f"{ROOT}/batch_1/oms/transaction/oms_transaction_week_{wk:%Y%m%d}.csv", TX_COLS, rows)

# ------------------------------------------------------------------ CRM: meetings (NDJSON)
def gen_meetings(days, batch, start_id, rate=0.07):
    mid, rows = start_id, []
    for d in days:
        for cid, c in clients.items():
            if dt.date.fromisoformat(c["onboarded_date"]) > d:
                continue
            if random.random() < rate:
                mid += 1
                rows.append({"meeting_id": mid, "client_id": cid, "advisor_id": c["primary_advisor_id"],
                             "meeting_ts": ts(d, random.randint(10, 17), 0).isoformat(),
                             "channel": random.choice(["IN_PERSON", "VIDEO", "PHONE"]),
                             "topics": random.sample(["PORTFOLIO_REVIEW", "TAX_PLANNING", "RISK_PROFILING",
                                                      "NEW_PRODUCT", "SIP_SETUP", "ESTATE_PLANNING"],
                                                     random.randint(1, 3))})
    os.makedirs(f"{ROOT}/{batch}/crm/meeting", exist_ok=True)
    with open(f"{ROOT}/{batch}/crm/meeting/crm_meetings_{days[-1]:%Y%m%d}.ndjson", "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    return mid


last_mid = gen_meetings(bdays(B1_START, B1_END), "batch_1", 30000)

# ================================================================== batch_2 (incremental)
b2 = bdays(B2_START, B2_END)
# client changes -> SCD2
changed = []
c = clients[1002]; c["risk_profile"] = "MODERATE"; c["updated_at"] = "2026-09-29 11:00:00"; changed.append(c)
c = clients[1011]; old = c["primary_advisor_id"]
c["primary_advisor_id"] = next(a for a in adv_by_city[c["city"].strip().title()] if a != old)
c["updated_at"] = "2026-09-29 11:05:00"; changed.append(c)
c = clients[1020]; c["city"] = "Bangalore"; c["segment"] = "UHNI"; c["updated_at"] = "2026-09-30 09:30:00"; changed.append(c)
write_csv(f"{ROOT}/batch_2/crm/client/crm_client_delta_20261002.csv", CL_COLS,
          [[c[k] for k in CL_COLS] for c in changed])

# pending applications finish -> new accounts, holders, events
new_accts, new_holders, ev2, new_open = [], [], [], {}
for app, cid, atype, stage in pending:
    aid += 1
    base = dt.date(2026, 9, 28)
    if stage == "KYC_SUBMITTED":
        ev2.append([app, cid, atype, "", "KYC_APPROVED", ts(base)])
    ev2.append([app, cid, atype, aid, "ACCOUNT_OPENED", ts(base + dt.timedelta(days=1))])
    city = clients[cid]["city"].strip().title()
    new_accts.append([aid, cid, atype, "INR", "ACTIVE", str(base + dt.timedelta(days=1)), "",
                      branch_by_city[city], f"{base + dt.timedelta(days=1)} 18:00:00"])
    new_holders.append([aid, cid, "PRIMARY", 100.00])
    acc_type[aid] = atype
    new_open[aid] = base + dt.timedelta(days=1)
# one account closes
closing = next(a for a in accounts if a[0] == 50015)
closing = closing[:4] + ["CLOSED", closing[5], "2026-10-01", closing[7], "2026-10-01 18:00:00"]
write_csv(f"{ROOT}/batch_2/core/account/core_account_delta_20261002.csv", AC_COLS, new_accts + [closing])
write_csv(f"{ROOT}/batch_2/core/account_holder/core_account_holder_delta_20261002.csv",
          ["account_id", "client_id", "holder_role", "ownership_pct"], new_holders)
write_csv(f"{ROOT}/batch_2/core/application/core_application_events_20261002.csv", APP_COLS, ev2)

active2 = [a for a in active if a != 50015] + list(new_open)
weeks2 = gen_txns(b2, active2, "batch_2", new_open)
for wk, rows in weeks2.items():
    write_csv(f"{ROOT}/batch_2/oms/transaction/oms_transaction_week_{wk:%Y%m%d}.csv", TX_COLS, rows)
gen_meetings(b2, "batch_2", last_mid)

print("clients", len(clients), "accounts", len(accounts) + len(new_accts), "holders", len(holders) + len(new_holders),
      "txns b1", sum(len(v) for v in weeks1.values()), "txns b2", sum(len(v) for v in weeks2.values()))
