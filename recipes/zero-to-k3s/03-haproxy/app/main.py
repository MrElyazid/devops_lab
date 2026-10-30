from fastapi import FastAPI
import psycopg2
import os

app = FastAPI()

DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]


def get_conn():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


@app.get("/items")
def list_items():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, name, price FROM items ORDER BY id")
    rows = [{"id": r[0], "name": r[1], "price": float(r[2])} for r in cur.fetchall()]
    cur.close()
    conn.close()
    return rows


@app.get("/items/{item_id}")
def get_item(item_id: int):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, name, price FROM items WHERE id = %s", (item_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if row is None:
        return {"error": "not found"}, 404
    return {"id": row[0], "name": row[1], "price": float(row[2])}
