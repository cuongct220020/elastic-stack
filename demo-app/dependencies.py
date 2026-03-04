from fastapi import Request

async def get_current_user(request: Request):
    """
    Giả lập lấy thông tin user đang thực hiện request (RẤT QUAN TRỌNG CHO AUDIT LOGS).
    Trong thực tế, bạn sẽ decode JWT Token từ request.headers.
    """
    # Mặc định lấy từ header 'X-User-ID', nếu không có thì gán là 'anonymous_user'
    return request.headers.get("X-User-ID", "anonymous_user")
