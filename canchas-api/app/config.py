from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "mysql+pymysql://root:password@localhost:3306/canchas_reservas"
    secret_key: str = "cambiar-esto-en-produccion"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24  # 24 horas
    
    # Campo para la API Key de Gemini
    gemini_api_key: str = ""

    # URL pública del servidor, usada para armar enlaces a archivos estáticos
    # (fotos de canchas, comprobantes, etc.). Debe ser la IP de la red local,
    # no 127.0.0.1, para que los celulares puedan cargar las imágenes.
    api_base_url: str = "http://192.168.5.3:8000"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()