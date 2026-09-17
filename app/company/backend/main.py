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
        "message": "EX8 Company Backend GitHub Actions 배포 성공",
        "status": "success"
    }


@app.get("/health")
def health():
    return {
        "status": "ok"
    }