"""Alembic 환경 — models.Base.metadata 를 대상으로, DATABASE_URL 환경변수 사용."""

import os
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

from models import Base  # noqa: E402

config = context.config

# DB URL 은 환경변수에서 주입 (alembic.ini 에 비밀정보를 두지 않음)
db_url = os.environ.get("DATABASE_URL", "sqlite:///./dev.db")
config.set_main_option("sqlalchemy.url", db_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=db_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            render_as_batch=connection.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
