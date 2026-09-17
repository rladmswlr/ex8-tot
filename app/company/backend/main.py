from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def root():
    return {
        "message": "EX8 Company Backend",
        "status": "success"
    }


@app.get("/api")
def api():
    return {
        "message": "EX8 Company Backend API",
        "status": "success"
    }


@app.get("/health")
def health():
    return {
        "status": "ok"
    }