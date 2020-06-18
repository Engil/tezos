import pytest
from tools import utils, constants
from launchers.sandbox import Sandbox
from . import protocol

BAKE_ARGS = ['--max-priority', '512', '--minimal-timestamp']
NUM_NODES = 3
PARAMS = constants.NODE_PARAMS
BLOCKS_PER_CYCLE = 2
PATH_FORGE_OPERATION = '/chains/main/blocks/head/helpers/forge/operations'


@pytest.mark.multinode
@pytest.mark.incremental
class TestDoubleEndorsement:
    """Constructs a double endorsement and builds evidence."""

    def test_init(self, sandbox: Sandbox):
        for i in range(NUM_NODES):
            sandbox.add_node(i, params=PARAMS)
        protocol.activate(sandbox.client(0), activate_in_the_past=True)
        for i in range(1, NUM_NODES):
            utils.remember_baker_contracts(sandbox.client(i))
        sandbox.client(0).bake('baker1', BAKE_ARGS)

    def test_level(self, sandbox: Sandbox):
        level = 2
        for client in sandbox.all_clients():
            assert utils.check_level(client, level)

    def test_terminate_nodes_1_and_2(self, sandbox: Sandbox):
        sandbox.node(1).terminate()
        sandbox.node(2).terminate()

    def test_bake_node_0(self, sandbox: Sandbox):
        """Client 0 bakes block A at level 3, not communicated to 1 and 2
        Inject an endorsement to ensure a different hash"""
        sandbox.client(0).endorse('baker1')
        sandbox.client(0).bake('baker1', BAKE_ARGS)

    def test_endorse_node_0(self, sandbox: Sandbox, session: dict):
        """bootstrap1 builds an endorsement for block A"""
        client = sandbox.client(0)
        client.endorse('baker1')
        mempool = client.get_mempool()
        endorsement = mempool['applied'][0]
        session['endorsement1'] = endorsement

    def test_terminate_node_0(self, sandbox: Sandbox):
        sandbox.node(0).terminate()

    def test_restart_node_2(self, sandbox: Sandbox):
        sandbox.node(2).run()
        assert sandbox.client(2).check_node_listening()

    def test_bake_node_2(self, sandbox: Sandbox):
        """Client 2 bakes block B at level 3, not communicated to 0 and 1"""
        sandbox.client(2).bake('baker1', BAKE_ARGS)

    def test_endorse_node_2(self, sandbox: Sandbox, session: dict):
        """bootstrap1 builds an endorsement for block B"""
        client = sandbox.client(2)
        client.endorse('baker1')
        mempool = client.get_mempool()
        endorsement = mempool['applied'][0]
        session['endorsement2'] = endorsement
        sandbox.client(2).endorse('baker2')

    def test_restart_all(self, sandbox: Sandbox):
        sandbox.node(0).run()
        sandbox.node(1).run()
        sandbox.client(0).check_node_listening()
        sandbox.client(1).check_node_listening()

    def test_check_level(self, sandbox: Sandbox):
        """All nodes are at level 3, head is either block A or B"""
        level = 3
        for client in sandbox.all_clients():
            assert utils.check_level(client, level)

    def test_forge_accusation(self, sandbox: Sandbox, session: dict):
        """Forge and inject a double endorsement evidence operation"""
        client = sandbox.client(1)
        head_hash = client.get_head()['hash']

        # Extract the `Endorsement` ops and the slot out of the
        # `Endorsement_with_slot` ops
        endorsement1 = session['endorsement1']['contents'][0]['endorsement']
        endorsement2 = session['endorsement2']['contents'][0]['endorsement']
        slot = session['endorsement1']['contents'][0]['slot']

        operation = {
            'branch': head_hash,
            'contents': [
                {
                    'kind': 'double_endorsement_evidence',
                    'op1': endorsement1,
                    'op2': endorsement2,
                    'slot': slot,
                }
            ],
        }

        operation_hex_string = client.rpc(
            'post', PATH_FORGE_OPERATION, data=operation
        )
        assert isinstance(operation_hex_string, str)
        sender_sk_long = constants.IDENTITIES['bootstrap1']['secret']
        sender_sk = sender_sk_long[len('unencrypted:') :]
        signed_op = utils.sign_operation(operation_hex_string, sender_sk)
        op_hash = client.rpc('post', 'injection/operation', signed_op)
        assert isinstance(op_hash, str)
        session['operation'] = op_hash

    def test_operation_applied(self, sandbox, session):
        """Check operation is in mempool"""
        client = sandbox.client(1)
        assert utils.check_mempool_contains_operations(
            client, [session['operation']]
        )


@pytest.mark.multinode
@pytest.mark.incremental
class TestDoubleEndorsementBeforeBakerKeyChange:
    """Constructs a double endorsement right before baker consensus key change
    is applied and builds evidence."""

    def test_init(self, sandbox):
        for i in range(NUM_NODES):
            sandbox.add_node(i, params=PARAMS)
        parameters = protocol.PARAMETERS
        parameters['blocks_per_cycle'] = BLOCKS_PER_CYCLE
        parameters['blocks_per_roll_snapshot'] = BLOCKS_PER_CYCLE
        protocol.activate(sandbox.client(0), parameters)
        utils.synchronize(sandbox.all_clients())
        for i in range(1, NUM_NODES):
            utils.remember_baker_contracts(sandbox.client(i))
        sandbox.client(0).bake('baker1', BAKE_ARGS)

    def test_level(self, sandbox):
        level = 2
        for client in sandbox.all_clients():
            assert utils.check_level(client, level)

    def test_change_consensus_key(self, sandbox):
        client = sandbox.client(0)
        client.gen_key('new_key')
        client.set_baker_consensus_key('baker1', 'new_key')
        client.bake('baker1', BAKE_ARGS)

    def test_bake_before_consensus_key_change_applied(self, sandbox, session):
        """Bake before the end of cycle [preserved_cycles + 2],
        right before the consensus key change is applied"""
        client = sandbox.client(0)
        preserved_cycles = protocol.PARAMETERS['preserved_cycles']
        utils.bake_until_nth_cycle_end(
            preserved_cycles + 1, client, 'baker1', BLOCKS_PER_CYCLE, BAKE_ARGS
        )
        current_level = client.get_level()
        delta = BLOCKS_PER_CYCLE - current_level
        utils.bake_many(delta - 1, client, 'baker1', BAKE_ARGS)
        session['level'] = client.get_level()

    def test_level_synced(self, sandbox, session):
        for client in sandbox.all_clients():
            assert utils.check_level(client, session['level'])

    def test_baker_consensus_key_has_not_changed_yet(self, sandbox):
        previous_key = constants.IDENTITIES['baker1_key']['public']
        baker_hash = constants.BOOTSTRAP_BAKERS[0]['hash']
        # baker bakes block with the consensus key at offset 1 (the next block)
        current_key = sandbox.client(0).get_baker_consensus_key(
            baker_hash, offset=1
        )
        assert current_key == previous_key

    def test_terminate_nodes_1_and_2(self, sandbox):
        sandbox.node(1).terminate()
        sandbox.node(2).terminate()

    def test_bake_node_0(self, sandbox):
        """Client 0 bakes block A at level 3, not communicated to 1 and 2
        Inject an endorsement to ensure a different hash"""
        sandbox.client(0).endorse('baker1')
        sandbox.client(0).bake('baker1', BAKE_ARGS)

    def test_endorse_node_0(self, sandbox, session):
        """bootstrap1 builds an endorsement for block A"""
        client = sandbox.client(0)
        client.endorse('baker1')
        mempool = client.get_mempool()
        endorsement = mempool['applied'][0]
        session['endorsement1'] = endorsement

    def test_terminate_node_0(self, sandbox):
        sandbox.node(0).terminate()

    def test_restart_node_2(self, sandbox):
        sandbox.node(2).run()
        assert sandbox.client(2).check_node_listening()

    def test_bake_node_2(self, sandbox):
        """Client 2 bakes block B at the next level, not communicated to 0
        and 1"""
        sandbox.client(2).bake('baker1', BAKE_ARGS)

    def test_endorse_node_2(self, sandbox, session):
        """bootstrap1 builds an endorsement for block B"""
        client = sandbox.client(2)
        client.endorse('baker1')
        mempool = client.get_mempool()
        endorsement = mempool['applied'][0]
        session['endorsement2'] = endorsement
        sandbox.client(2).endorse('baker2')

    def test_restart_all(self, sandbox):
        sandbox.node(0).run()
        sandbox.node(1).run()
        sandbox.client(0).check_node_listening()
        sandbox.client(1).check_node_listening()

    def test_check_level(self, sandbox, session):
        """All nodes are at the next level, head is either block A or B"""
        level = session['level'] + 1
        for client in sandbox.all_clients():
            assert utils.check_level(client, level)

    def test_forge_accusation(self, sandbox, session):
        """Forge and inject a double endorsement evidence operation"""
        client = sandbox.client(1)
        head_hash = client.get_head()['hash']

        # Extract the `Endorsement` ops and the slot out of the
        # `Endorsement_with_slot` ops
        endorsement1 = session['endorsement1']['contents'][0]['endorsement']
        endorsement2 = session['endorsement2']['contents'][0]['endorsement']
        slot = session['endorsement1']['contents'][0]['slot']

        operation = {
            'branch': head_hash,
            'contents': [
                {
                    'kind': 'double_endorsement_evidence',
                    'op1': endorsement1,
                    'op2': endorsement2,
                    'slot': slot,
                }
            ],
        }

        operation_hex_string = client.rpc(
            'post', PATH_FORGE_OPERATION, data=operation
        )
        assert isinstance(operation_hex_string, str)
        sender_sk_long = constants.IDENTITIES['bootstrap1']['secret']
        sender_sk = sender_sk_long[len('unencrypted:') :]
        signed_op = utils.sign_operation(operation_hex_string, sender_sk)
        op_hash = client.rpc('post', 'injection/operation', signed_op)
        assert isinstance(op_hash, str)
        session['operation'] = op_hash

    def test_operation_applied(self, sandbox, session):
        """Check operation is in mempool"""
        client = sandbox.client(1)
        assert utils.check_mempool_contains_operations(
            client, [session['operation']]
        )


@pytest.mark.multinode
@pytest.mark.incremental
class TestDoubleEndorsementAfterBakerKeyChange:
    """Constructs a double endorsement right after baker consensus key change
    is applied and builds evidence."""

    def test_init(self, sandbox):
        for i in range(NUM_NODES):
            sandbox.add_node(i, params=PARAMS)
        parameters = protocol.PARAMETERS
        parameters['blocks_per_cycle'] = BLOCKS_PER_CYCLE
        parameters['blocks_per_roll_snapshot'] = BLOCKS_PER_CYCLE
        protocol.activate(sandbox.client(0), parameters)
        utils.synchronize(sandbox.all_clients())
        for i in range(1, NUM_NODES):
            utils.remember_baker_contracts(sandbox.client(i))
        sandbox.client(0).bake('baker1', BAKE_ARGS)

    def test_level(self, sandbox):
        level = 2
        for client in sandbox.all_clients():
            assert utils.check_level(client, level)

    def test_change_consensus_key(self, sandbox, session):
        client = sandbox.client(0)
        client.gen_key('new_key')
        address = client.show_address('new_key', ['--show-secret'])
        session['new_key_pk'] = address.public_key
        session['new_key_sk'] = address.secret_key
        client.set_baker_consensus_key('baker1', 'new_key')
        client.bake('baker1', BAKE_ARGS)

    def test_bake_after_consensus_key_change_applied(self, sandbox, session):
        """Bake to the end of cycle [preserved_cycles + 2],
        right after the consensus key change is applied"""
        client = sandbox.client(0)
        preserved_cycles = protocol.PARAMETERS['preserved_cycles']
        utils.bake_until_nth_cycle_end(
            preserved_cycles + 2, client, 'baker1', BLOCKS_PER_CYCLE, BAKE_ARGS
        )
        session['level'] = client.get_level()

    def test_level_synced(self, sandbox, session):
        for client in sandbox.all_clients():
            assert utils.check_level(client, session['level'])

    def test_baker_consensus_key_has_changed(self, sandbox, session):
        new_key = session['new_key_pk']
        baker_hash = constants.BOOTSTRAP_BAKERS[0]['hash']
        # baker bakes block with the consensus key at offset 1 (the next block)
        current_key = sandbox.client(0).get_baker_consensus_key(
            baker_hash, offset=1
        )
        assert current_key == new_key

    def test_terminate_nodes_1_and_2(self, sandbox):
        sandbox.node(1).terminate()
        sandbox.node(2).terminate()

    def test_bake_node_0(self, sandbox):
        """Client 0 bakes block A at level 3, not communicated to 1 and 2
        Inject an endorsement to ensure a different hash"""
        sandbox.client(0).endorse('baker1')
        sandbox.client(0).bake('baker1', BAKE_ARGS)

    def test_endorse_node_0(self, sandbox, session):
        """bootstrap1 builds an endorsement for block A"""
        client = sandbox.client(0)
        client.endorse('baker1')
        mempool = client.get_mempool()
        endorsement = mempool['applied'][0]
        session['endorsement1'] = endorsement

    def test_terminate_node_0(self, sandbox):
        sandbox.node(0).terminate()

    def test_restart_node_2(self, sandbox):
        sandbox.node(2).run()
        assert sandbox.client(2).check_node_listening()

    def test_bake_node_2(self, sandbox, session):
        """Client 2 bakes block B at the next level, not communicated to 0
        and 1"""
        client = sandbox.client(2)
        client.import_secret_key('new_key', session['new_key_sk'])
        client.bake('baker1', BAKE_ARGS)

    def test_endorse_node_2(self, sandbox, session):
        """bootstrap1 builds an endorsement for block B"""
        client = sandbox.client(2)
        client.endorse('baker1')
        mempool = client.get_mempool()
        endorsement = mempool['applied'][0]
        session['endorsement2'] = endorsement
        sandbox.client(2).endorse('baker2')

    def test_restart_all(self, sandbox):
        sandbox.node(0).run()
        sandbox.node(1).run()
        sandbox.client(0).check_node_listening()
        sandbox.client(1).check_node_listening()

    def test_check_level(self, sandbox, session):
        """All nodes are at the next level, head is either block A or B"""
        level = session['level'] + 1
        for client in sandbox.all_clients():
            assert utils.check_level(client, level)

    def test_forge_accusation(self, sandbox, session):
        """Forge and inject a double endorsement evidence operation"""
        client = sandbox.client(1)
        head_hash = client.get_head()['hash']

        # Extract the `Endorsement` ops and the slot out of the
        # `Endorsement_with_slot` ops
        endorsement1 = session['endorsement1']['contents'][0]['endorsement']
        endorsement2 = session['endorsement2']['contents'][0]['endorsement']
        slot = session['endorsement1']['contents'][0]['slot']

        operation = {
            'branch': head_hash,
            'contents': [
                {
                    'kind': 'double_endorsement_evidence',
                    'op1': endorsement1,
                    'op2': endorsement2,
                    'slot': slot,
                }
            ],
        }

        operation_hex_string = client.rpc(
            'post', PATH_FORGE_OPERATION, data=operation
        )
        assert isinstance(operation_hex_string, str)
        sender_sk_long = constants.IDENTITIES['bootstrap1']['secret']
        sender_sk = sender_sk_long[len('unencrypted:') :]
        signed_op = utils.sign_operation(operation_hex_string, sender_sk)
        op_hash = client.rpc('post', 'injection/operation', signed_op)
        assert isinstance(op_hash, str)
        session['operation'] = op_hash

    def test_operation_applied(self, sandbox: Sandbox, session: dict):
        """Check operation is in mempool"""
        client = sandbox.client(1)
        assert utils.check_mempool_contains_operations(
            client, [session['operation']]
        )