import os

# Edit these values or set them as environment variables.
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "Yasha26##"),
    "dbname": os.getenv("DB_NAME", "expense_tracker"),
}
SECRET_KEY = os.getenv("SECRET_KEY", "rootuser")
