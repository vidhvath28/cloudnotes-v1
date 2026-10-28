from flask import Flask, render_template, send_from_directory, jsonify
from dotenv import load_dotenv
from api.routes import api_bp
from utils.helpers import get_db_connection
import os
import socket

load_dotenv()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.environ.get("UPLOAD_FOLDER", os.path.join(BASE_DIR, "uploads"))

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ["SECRET_KEY"]
app.config["DATABASE_URL"] = os.environ["DATABASE_URL"]
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024

app.register_blueprint(api_bp, url_prefix="/api")

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route("/")
def home():
    return render_template("index.html")

@app.route("/notes")
def notes_page():
    return render_template("notes.html")

@app.route("/uploads/<path:filename>")
def uploaded_file(filename):
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)

@app.route("/healthz")
def healthz():
    conn = get_db_connection(app.config["DATABASE_URL"])
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
    finally:
        conn.close()
    return jsonify({"status": "ok", "host": socket.gethostname(), "pid": os.getpid()})

if __name__ == "__main__":
    app.run(
        debug=os.environ.get("FLASK_DEBUG") == "1",
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "5000")),
    )
