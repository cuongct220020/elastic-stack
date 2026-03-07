from fastapi import Request

async def get_current_user(request: Request):
    return request.headers.get("X-User-ID", "anonymous_user")
