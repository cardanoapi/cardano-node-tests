import logging

import pytest

from cardano_node_tests.cluster_management import cluster_management
from cardano_node_tests.utils import governance_setup
from cardano_node_tests.utils import governance_utils

LOGGER = logging.getLogger(__name__)


@pytest.fixture
def cluster_use_committee(
    cluster_manager: cluster_management.ClusterManager,
) -> governance_utils.GovClusterT:
    """Mark governance committee as "in use"."""
    cluster_obj = cluster_manager.get(
        use_resources=[
            cluster_management.Resources.COMMITTEE,
        ]
    )
    governance_data = governance_setup.get_default_governance(
        cluster_manager=cluster_manager, cluster_obj=cluster_obj
    )
    return cluster_obj, governance_data


@pytest.fixture
def cluster_use_dreps(
    cluster_manager: cluster_management.ClusterManager,
) -> governance_utils.GovClusterT:
    """Mark governance DReps as "in use"."""
    cluster_obj = cluster_manager.get(
        use_resources=[
            cluster_management.Resources.DREPS,
        ]
    )
    governance_data = governance_setup.get_default_governance(
        cluster_manager=cluster_manager, cluster_obj=cluster_obj
    )
    return cluster_obj, governance_data


@pytest.fixture
def cluster_use_governance(
    cluster_manager: cluster_management.ClusterManager,
) -> governance_utils.GovClusterT:
    """Mark whole governance as "in use"."""
    cluster_obj = cluster_manager.get(
        use_resources=[
            cluster_management.Resources.COMMITTEE,
            cluster_management.Resources.DREPS,
            *cluster_management.Resources.ALL_POOLS,
        ]
    )
    governance_data = governance_setup.get_default_governance(
        cluster_manager=cluster_manager, cluster_obj=cluster_obj
    )
    governance_utils.wait_delayed_ratification(cluster_obj=cluster_obj)
    return cluster_obj, governance_data


@pytest.fixture
def cluster_lock_governance(
    cluster_manager: cluster_management.ClusterManager,
) -> governance_utils.GovClusterT:
    """Mark whole governance as "locked"."""
    cluster_obj = cluster_manager.get(
        use_resources=cluster_management.Resources.ALL_POOLS,
        lock_resources=[cluster_management.Resources.COMMITTEE, cluster_management.Resources.DREPS],
    )
    governance_data = governance_setup.get_default_governance(
        cluster_manager=cluster_manager, cluster_obj=cluster_obj
    )
    governance_utils.wait_delayed_ratification(cluster_obj=cluster_obj)
    return cluster_obj, governance_data


@pytest.fixture
def cluster_lock_governance_plutus(
    cluster_manager: cluster_management.ClusterManager,
) -> governance_utils.GovClusterT:
    """Mark whole governance and Plutus as "locked"."""
    cluster_obj = cluster_manager.get(
        use_resources=cluster_management.Resources.ALL_POOLS,
        lock_resources=[
            cluster_management.Resources.COMMITTEE,
            cluster_management.Resources.DREPS,
            cluster_management.Resources.PLUTUS,
        ],
    )
    governance_data = governance_setup.get_default_governance(
        cluster_manager=cluster_manager, cluster_obj=cluster_obj
    )
    governance_utils.wait_delayed_ratification(cluster_obj=cluster_obj)
    return cluster_obj, governance_data
