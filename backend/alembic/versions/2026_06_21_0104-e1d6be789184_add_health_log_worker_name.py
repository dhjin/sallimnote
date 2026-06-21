"""add health log worker_name

Revision ID: e1d6be789184
Revises: 3a54155f8fa6
Create Date: 2026-06-21 01:04:34.563746

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e1d6be789184'
down_revision: Union[str, None] = '3a54155f8fa6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('neonatal_health_log', schema=None) as batch_op:
        batch_op.add_column(sa.Column('worker_name', sa.String(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table('neonatal_health_log', schema=None) as batch_op:
        batch_op.drop_column('worker_name')
