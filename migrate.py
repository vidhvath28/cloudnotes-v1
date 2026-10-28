"""Apply database migrations: python migrate.py"""
import os

from dotenv import load_dotenv

from utils.helpers import run_migrations

load_dotenv()

if __name__ == "__main__":
    run_migrations(os.environ["DATABASE_URL"])
    print("migrations up to date")
