"""Rewind - Database Time Machine & Recovery System (Streamlit GUI).
Users log in with their ORACLE credentials, so every change is attributed to the real DB user.
Run:  streamlit run app.py
"""
import oracledb
import pandas as pd
import streamlit as st

st.set_page_config(page_title="Rewind", page_icon="âª", layout="wide")
S = "rewind"  # schema name

PAGES_BY_ROLE = {
    "ADMIN":   ["Admin Dashboard", "Database Activity Timeline", "Change History", "Before vs After",
                "Record Recovery", "Suspicious Activity", "User Activity & Audit Logs", "Simulate Changes"],
    "AUDITOR": ["Admin Dashboard", "Database Activity Timeline", "Change History", "Before vs After",
                "Suspicious Activity", "User Activity & Audit Logs"],
    "HR":      ["Simulate Changes"],
    "NONE":    ["Simulate Changes"],
}


# ---------------------------------------------------------------- helpers
def query(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or {})
        cols = [c[0].lower() for c in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=cols)


def db_error(e):
    err = e.args[0]
    st.error(getattr(err, "message", str(err)))


def login():
    st.title("Rewind - Database Time Machine")
    st.caption("Log in with your Oracle database account")
    with st.form("login"):
        dsn = st.text_input("DSN", "localhost:1521/XEPDB1")
        user = st.text_input("Username", "rw_admin")
        pwd = st.text_input("Password", type="password")
        if st.form_submit_button("Login"):
            try:
                conn = oracledb.connect(user=user, password=pwd, dsn=dsn)
                with conn.cursor() as cur:
                    role = cur.callfunc(f"{S}.rewind_pkg.my_role", str)
                st.session_state.update(conn=conn, user=user.upper(), role=role)
                st.rerun()
            except oracledb.DatabaseError as e:
                db_error(e)


# ---------------------------------------------------------------- pages
def dashboard(conn):
    st.header("Admin Dashboard")
    total = query(conn, f"SELECT COUNT(DISTINCT change_group) c FROM {S}.audit_log").c[0]
    today = query(conn, f"SELECT COUNT(DISTINCT change_group) c FROM {S}.audit_log "
                        "WHERE changed_on >= TRUNC(SYSDATE)").c[0]
    sus = query(conn, f"SELECT COUNT(*) c FROM {S}.suspicious_activity WHERE reviewed='N'").c[0]
    rec = query(conn, f"SELECT COUNT(*) c FROM {S}.recovery_log WHERE status='SUCCESS'").c[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total changes", int(total))
    c2.metric("Changes today", int(today))
    c3.metric("Unreviewed suspicious", int(sus))
    c4.metric("Successful recoveries", int(rec))

    left, right = st.columns(2)
    with left:
        st.subheader("Changes per user")
        df = query(conn, f"SELECT changed_by, total_changes FROM {S}.v_activity_by_user")
        if not df.empty:
            st.bar_chart(df.set_index("changed_by"))
    with right:
        st.subheader("Changes per day")
        df = query(conn, f"SELECT activity_day, changes FROM {S}.v_daily_activity ORDER BY 1")
        if not df.empty:
            st.line_chart(df.set_index("activity_day"))


def timeline(conn):
    st.header("Database Activity Timeline")

    date_range = st.date_input(
        "Select Date Range",
        value=(
            pd.Timestamp("2000-01-01").date(),
            pd.Timestamp.today().date()
        ),
        key="timeline_date_range"
    )

    if len(date_range) != 2:
        st.info("Please select both start date and end date.")
        return

    start_date, end_date = date_range

    if start_date > end_date:
        st.error("Invalid date range: Start date cannot be after end date.")
        return

    n = st.slider("Show latest N entries", 10, 500, 50)

    df = query(
        conn,
        f"SELECT changed_on, changed_by, operation, table_name, record_id, column_name, "
        f"old_value, new_value, is_suspicious, is_restored "
        f"FROM {S}.v_change_history "
        "WHERE changed_on >= TO_DATE(:start_date, 'YYYY-MM-DD') "
        "AND changed_on < TO_DATE(:end_date, 'YYYY-MM-DD') + 1 "
        "ORDER BY audit_id DESC FETCH FIRST :n ROWS ONLY",
        {
            "start_date": start_date.strftime("%Y-%m-%d"),
            "end_date": end_date.strftime("%Y-%m-%d"),
            "n": n
        }
    )

    st.dataframe(df, use_container_width=True, hide_index=True)


def history(conn):
    st.header("Change History")

    emp = st.number_input("Employee ID", min_value=0, value=101, step=1)

    date_range = st.date_input(
        "Select Date Range",
        value=(
            pd.Timestamp("2000-01-01").date(),
            pd.Timestamp.today().date()
        ),
        key="history_date_range"
    )

    if len(date_range) != 2:
        st.info("Please select both start date and end date.")
        return

    start_date, end_date = date_range
    if start_date > end_date:
        st.error("Invalid date range: Start date cannot be after end date.")
        return

    df = query(
        conn,
        f"SELECT audit_id, changed_on, operation, column_name, old_value, new_value, "
        f"changed_by, is_suspicious, is_restored "
        f"FROM {S}.v_change_history "
        "WHERE record_id = :id "
        "AND changed_on >= TO_DATE(:start_date, 'YYYY-MM-DD') "
        "AND changed_on < TO_DATE(:end_date, 'YYYY-MM-DD') + 1 "
        "ORDER BY audit_id DESC",
        {
            "id": int(emp),
            "start_date": start_date.strftime("%Y-%m-%d"),
            "end_date": end_date.strftime("%Y-%m-%d")
        }
    )

    if df.empty:
        st.info("No changes recorded for this employee in the selected date range.")
    else:
        st.dataframe(df, use_container_width=True, hide_index=True)



def compare(conn):
    st.header("Before vs After Comparison")
    df = query(conn, f"SELECT audit_id, change_group, record_id, column_name, changed_by FROM {S}.audit_log "
                     "WHERE operation='UPDATE' ORDER BY audit_id DESC FETCH FIRST 100 ROWS ONLY")
    if df.empty:
        st.info("No updates recorded yet.")
        return
    labels = {int(r.audit_id): f"#{r.audit_id} | employee {r.record_id} | {r.column_name} | by {r.changed_by}"
              for r in df.itertuples()}
    pick = st.selectbox("Select a change", list(labels), format_func=labels.get)
    row = df[df.audit_id == pick].iloc[0]
    detail = query(conn, f"SELECT column_name, old_value, new_value FROM {S}.audit_log "
                         "WHERE change_group = :g ORDER BY audit_id", {"g": row.change_group})
    detail.columns = ["Column", "Before", "After"]
    st.dataframe(detail, use_container_width=True, hide_index=True)
    one = query(conn, f"SELECT old_value, new_value FROM {S}.audit_log WHERE audit_id=:i", {"i": int(pick)})
    a, b = st.columns(2)
    a.metric("Before", one.old_value[0])
    b.metric("After", one.new_value[0])


def recovery(conn):
    st.header("Record Recovery")
    st.subheader("Restore an updated value")
    df = query(conn, f"SELECT audit_id, record_id, column_name, old_value, new_value, changed_by, changed_on "
                     f"FROM {S}.audit_log WHERE operation='UPDATE' AND is_restored='N' "
                     "ORDER BY audit_id DESC FETCH FIRST 50 ROWS ONLY")
    st.dataframe(df, use_container_width=True, hide_index=True)
    if not df.empty:
        pick = st.selectbox("Audit ID to restore", df.audit_id.tolist())
        if st.button("âª Restore previous value"):
            try:
                with conn.cursor() as cur:
                    cur.callproc(f"{S}.rewind_pkg.restore_value", [int(pick)])
                st.success(f"Change #{pick} restored.")
            except oracledb.DatabaseError as e:
                db_error(e)

    st.subheader("Restore a deleted employee")
    dele = query(conn, f"SELECT change_group, record_id, MIN(changed_by) deleted_by, MIN(changed_on) deleted_on "
                       f"FROM {S}.audit_log WHERE operation='DELETE' AND is_restored='N' "
                       "GROUP BY change_group, record_id ORDER BY 4 DESC")
    st.dataframe(dele, use_container_width=True, hide_index=True)
    if not dele.empty:
        grp = st.selectbox("Change group", dele.change_group.tolist())
        if st.button("âª Restore deleted employee"):
            try:
                with conn.cursor() as cur:
                    cur.callproc(f"{S}.rewind_pkg.restore_deleted", [grp])
                st.success("Employee restored.")
            except oracledb.DatabaseError as e:
                db_error(e)


def suspicious(conn):
    st.header("Suspicious Activity")
    df = query(conn, f"SELECT sus_id, severity, reason, changed_by, record_id, column_name, old_value, "
                     f"new_value, detected_on, reviewed, reviewed_by FROM {S}.v_suspicious_details "
                     "ORDER BY sus_id DESC")
    st.dataframe(df, use_container_width=True, hide_index=True)
    open_ids = df[df.reviewed == "N"].sus_id.tolist() if not df.empty else []
    if open_ids:
        pick = st.selectbox("Mark as reviewed", open_ids)
        if st.button("Mark reviewed"):
            try:
                with conn.cursor() as cur:
                    cur.callproc(f"{S}.rewind_pkg.review_suspicious", [int(pick)])
                st.success("Marked as reviewed.")
                st.rerun()
            except oracledb.DatabaseError as e:
                db_error(e)


def logs(conn):
    st.header("User Activity & Audit Logs")
    t1, t2, t3 = st.tabs(["Activity by user", "Recovery log", "Full audit log"])
    with t1:
        st.dataframe(query(conn, f"SELECT * FROM {S}.v_activity_by_user"), use_container_width=True, hide_index=True)
    with t2:
        st.dataframe(query(conn, f"SELECT * FROM {S}.recovery_log ORDER BY recovery_id DESC"),
                     use_container_width=True, hide_index=True)
    with t3:
        df = query(conn, f"SELECT * FROM {S}.audit_log ORDER BY audit_id DESC")
        st.dataframe(df, use_container_width=True, hide_index=True)
        st.download_button("Download CSV", df.to_csv(index=False), "audit_log.csv", "text/csv")


def simulate(conn):
    st.header("Simulate Changes (demo data entry)")
    st.caption("Use this page to create changes that Rewind will record, e.g. set a wrong salary.")
    emps = query(conn, f"SELECT emp_id, emp_name, job_title, salary FROM {S}.employees ORDER BY emp_id")
    st.dataframe(emps, use_container_width=True, hide_index=True)
    if emps.empty:
        return
    emp = st.selectbox("Employee", emps.emp_id.tolist())
    sal = st.number_input("New salary", min_value=0.0, value=float(emps[emps.emp_id == emp].salary.iloc[0]), step=1000.0)
    c1, c2 = st.columns(2)
    if c1.button("Update salary"):
        try:
            with conn.cursor() as cur:
                cur.execute(f"UPDATE {S}.employees SET salary=:s WHERE emp_id=:e", {"s": sal, "e": int(emp)})
            conn.commit()
            st.success("Salary updated.")
        except oracledb.DatabaseError as e:
            conn.rollback()
            db_error(e)
    if c2.button("Delete employee"):
        try:
            with conn.cursor() as cur:
                cur.execute(f"DELETE FROM {S}.employees WHERE emp_id=:e", {"e": int(emp)})
            conn.commit()
            st.success("Employee deleted.")
        except oracledb.DatabaseError as e:
            conn.rollback()
            db_error(e)


PAGE_FUNCS = {
    "Admin Dashboard": dashboard, "Database Activity Timeline": timeline, "Change History": history,
    "Before vs After": compare, "Record Recovery": recovery, "Suspicious Activity": suspicious,
    "User Activity & Audit Logs": logs, "Simulate Changes": simulate,
}

# ---------------------------------------------------------------- main
if "conn" not in st.session_state:
    login()
else:
    conn, role = st.session_state["conn"], st.session_state["role"]
    st.sidebar.title("Rewind")
    st.sidebar.write(f"**User:** {st.session_state['user']}  \n**Role:** {role}")
    if st.sidebar.button("Logout"):
        conn.close()
        st.session_state.clear()
        st.rerun()
    page = st.sidebar.radio("Screens", PAGES_BY_ROLE.get(role, PAGES_BY_ROLE["NONE"]))
    try:
        PAGE_FUNCS[page](conn)
    except oracledb.DatabaseError as e:
        db_error(e)



