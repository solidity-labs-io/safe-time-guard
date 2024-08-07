// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/utils/SystemIntegrationFixture.sol";

contract RecoverySpellsIntegrationTest is SystemIntegrationFixture {
    using BytesHelper for bytes;

    function _initializeContract() private {
        IMulticall3.Call3[] memory calls3 = new IMulticall3.Call3[](4);

        calls3[0].target = address(guard);
        calls3[0].allowFailure = false;

        calls3[1].target = address(safe);
        calls3[1].allowFailure = false;

        calls3[2].target = address(safe);
        calls3[2].allowFailure = false;

        calls3[3].target = address(safe);
        calls3[3].allowFailure = false;

        calls3[0].callData = abi.encodeWithSelector(Guard.checkSafe.selector);

        calls3[1].callData = abi.encodeWithSelector(
            GuardManager.setGuard.selector, address(guard)
        );

        calls3[2].callData = abi.encodeWithSelector(
            ModuleManager.enableModule.selector, address(timelock)
        );

        calls3[3].callData = abi.encodeWithSelector(
            ModuleManager.enableModule.selector, recoverySpellAddress
        );

        bytes memory safeData =
            abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls3);

        bytes32 transactionHash = safe.getTransactionHash(
            multicall,
            0,
            safeData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            address(0),
            safe.nonce()
        );

        bytes memory collatedSignatures =
            signTxAllOwners(transactionHash, pk1, pk2, pk3);

        safe.checkNSignatures(transactionHash, safeData, collatedSignatures, 3);

        safe.execTransaction(
            multicall,
            0,
            safeData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            collatedSignatures
        );

        bytes memory guardBytes =
            SafeL2(payable(safe)).getStorageAt(GUARD_STORAGE_SLOT, 1);

        address guard = address(uint160(uint256(guardBytes.getFirstWord())));

        assertEq(guard, address(guard), "guard is not guard");
        assertTrue(
            safe.isModuleEnabled(address(timelock)), "timelock not a module"
        );
        assertTrue(
            safe.isModuleEnabled(recoverySpellAddress),
            "recovery spell not a module"
        );
    }

    function testCreateAddAndUseCounterfactualRecoverySpellRecoveryThresholdTwo(
    ) public {
        uint256 recoveryThresholdOwner = 2;

        recoverySpellAddress = recoveryFactory.calculateAddress(
            recoverySalt,
            recoveryOwners,
            address(safe),
            recoveryThreshold,
            recoveryThresholdOwner,
            recoveryDelay
        );

        IMulticall3.Call3[] memory calls3 = new IMulticall3.Call3[](4);

        calls3[0].target = address(guard);
        calls3[0].allowFailure = false;

        calls3[1].target = address(safe);
        calls3[1].allowFailure = false;

        calls3[2].target = address(safe);
        calls3[2].allowFailure = false;

        calls3[3].target = address(safe);
        calls3[3].allowFailure = false;

        calls3[0].callData = abi.encodeWithSelector(guard.checkSafe.selector);

        calls3[1].callData = abi.encodeWithSelector(
            GuardManager.setGuard.selector, address(guard)
        );

        calls3[2].callData = abi.encodeWithSelector(
            ModuleManager.enableModule.selector, address(timelock)
        );

        calls3[3].callData = abi.encodeWithSelector(
            ModuleManager.enableModule.selector, recoverySpellAddress
        );

        {
            bytes memory safeData =
                abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls3);

            bytes32 transactionHash = safe.getTransactionHash(
                multicall,
                0,
                safeData,
                Enum.Operation.DelegateCall,
                0,
                0,
                0,
                address(0),
                address(0),
                safe.nonce()
            );

            bytes memory collatedSignatures =
                signTxAllOwners(transactionHash, pk1, pk2, pk3);

            safe.checkNSignatures(
                transactionHash, safeData, collatedSignatures, 3
            );

            safe.execTransaction(
                multicall,
                0,
                safeData,
                Enum.Operation.DelegateCall,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                collatedSignatures
            );
        }

        {
            bytes memory guardBytes =
                SafeL2(payable(safe)).getStorageAt(GUARD_STORAGE_SLOT, 1);
            address guard = address(uint160(uint256(guardBytes.getFirstWord())));

            assertEq(guard, address(guard), "guard is not guard");
        }
        assertTrue(
            safe.isModuleEnabled(address(timelock)), "timelock not a module"
        );
        assertTrue(
            safe.isModuleEnabled(recoverySpellAddress),
            "recovery spell not a module"
        );

        /// create spell
        assertEq(
            address(
                recoveryFactory.createRecoverySpell(
                    recoverySalt,
                    recoveryOwners,
                    address(safe),
                    recoveryThreshold,
                    recoveryThresholdOwner,
                    recoveryDelay
                )
            ),
            recoverySpellAddress,
            "recovery spell address mismatch"
        );

        RecoverySpell spell = RecoverySpell(recoverySpellAddress);
        assertEq(spell.delay(), recoveryDelay, "delay mismatch");

        /// initiate recovery
        spell.initiateRecovery();

        vm.warp(spell.delay() + block.timestamp + 1);

        /// sign recovery transaction
        bytes32[] memory r = new bytes32[](recoveryPrivateKeys.length);
        bytes32[] memory s = new bytes32[](recoveryPrivateKeys.length);
        uint8[] memory v = new uint8[](recoveryPrivateKeys.length);

        bytes32 digest = spell.getDigest();

        for (uint256 i = 0; i < recoveryPrivateKeys.length; i++) {
            (v[i], r[i], s[i]) = vm.sign(recoveryPrivateKeys[i], digest);
        }

        vm.expectEmit(true, true, true, true, address(spell));
        emit SafeRecovered(block.timestamp);

        /// execute recovery transaction
        spell.executeRecovery(address(1), v, r, s);

        assertFalse(
            safe.isModuleEnabled(recoverySpellAddress),
            "recovery spell should be removed as a module after execution"
        );

        for (uint256 i = 0; i < owners.length; i++) {
            assertFalse(
                safe.isOwner(owners[i]),
                "owner should be removed after recovery"
            );
        }

        for (uint256 i = 0; i < owners.length; i++) {
            assertTrue(
                safe.isOwner(recoveryOwners[i]),
                "recovery owners should be added after recovery"
            );
        }

        assertEq(spell.getOwners().length, 0, "owners should be empty");
        assertEq(
            spell.recoveryInitiated(),
            type(uint256).max,
            "recovery initiated should be uint max"
        );

        assertEq(safe.getThreshold(), recoveryThreshold, "threshold incorrect");
    }

    function testRecoverySpellRotatesAllSigners()
        public
        returns (RecoverySpell recovery)
    {
        _initializeContract();

        recovery = recoveryFactory.createRecoverySpell(
            recoverySalt,
            recoveryOwners,
            address(safe),
            recoveryThreshold,
            RECOVERY_THRESHOLD_OWNERS,
            recoveryDelay
        );

        assertEq(
            recoverySpellAddress,
            address(recovery),
            "recovery spell address incorrect"
        );
        assertTrue(
            address(recovery).code.length != 0, "recovery spell not created"
        );

        vm.prank(recoveryOwners[0]);
        recovery.initiateRecovery();

        assertEq(
            recovery.recoveryInitiated(),
            block.timestamp,
            "recovery not initiated"
        );

        vm.warp(block.timestamp + recoveryDelay + 1);

        recovery.executeRecovery(address(1));

        assertFalse(
            safe.isModuleEnabled(recoverySpellAddress),
            "recovery spell should be removed after execution"
        );

        for (uint256 i = 0; i < owners.length; i++) {
            assertFalse(
                safe.isOwner(owners[i]),
                "owner should be removed after recovery"
            );
        }

        for (uint256 i = 0; i < recoveryOwners.length; i++) {
            assertTrue(
                safe.isOwner(recoveryOwners[i]),
                "recovery owner should be an owner"
            );
        }

        assertEq(recovery.getOwners().length, 0, "owners should be empty");
        assertEq(
            recovery.recoveryInitiated(),
            type(uint256).max,
            "recovery initiated should be uint max"
        );

        assertEq(safe.getThreshold(), recoveryThreshold, "threshold incorrect");
    }

    function testRecoverySpellRecoverFailsNotEnoughSignatures() public {
        uint256 recoveryThresholdOwners = 2;
        recoverySpellAddress = recoveryFactory.calculateAddress(
            recoverySalt,
            recoveryOwners,
            address(safe),
            recoveryThreshold,
            recoveryThresholdOwners,
            recoveryDelay
        );

        _initializeContract();

        RecoverySpell recovery = recoveryFactory.createRecoverySpell(
            recoverySalt,
            recoveryOwners,
            address(safe),
            recoveryThreshold,
            recoveryThresholdOwners,
            recoveryDelay
        );

        recovery.initiateRecovery();

        vm.warp(block.timestamp + recoveryDelay - 1);

        vm.expectRevert("RecoverySpell: Recovery not ready");
        recovery.executeRecovery(
            address(1), new uint8[](0), new bytes32[](0), new bytes32[](0)
        );

        /// now timestamp exactly at recovery delay
        vm.warp(block.timestamp + 1);
        vm.expectRevert("RecoverySpell: Recovery not ready");
        recovery.executeRecovery(
            address(1), new uint8[](0), new bytes32[](0), new bytes32[](0)
        );

        /// now timestamp is exactly 1 second past recovery delay and recovery can commence
        vm.warp(block.timestamp + 1);

        vm.expectRevert("RecoverySpell: Signatures required");
        recovery.executeRecovery(address(1));

        vm.expectRevert("RecoverySpell: Not enough signatures");
        recovery.executeRecovery(
            address(1), new uint8[](0), new bytes32[](0), new bytes32[](0)
        );

        vm.expectRevert("RecoverySpell: Invalid signature parameters");
        recovery.executeRecovery(
            address(1), new uint8[](1), new bytes32[](0), new bytes32[](0)
        );

        bytes32[] memory r = new bytes32[](recoveryPrivateKeys.length);
        bytes32[] memory s = new bytes32[](recoveryPrivateKeys.length);
        uint8[] memory v = new uint8[](recoveryPrivateKeys.length);

        bytes32 digest = recovery.getDigest();
        for (uint256 i = 0; i < recoveryPrivateKeys.length; i++) {
            (v[i], r[i], s[i]) = vm.sign(recoveryPrivateKeys[i], digest);
        }

        /// final signature duplicate
        v[v.length - 1] = v[v.length - 2];
        r[r.length - 1] = r[r.length - 2];
        s[s.length - 1] = s[s.length - 2];

        vm.expectRevert("RecoverySpell: Duplicate signature");
        recovery.executeRecovery(address(1), v, r, s);

        v[0] += 2;
        vm.expectRevert("RecoverySpell: Invalid signature");
        recovery.executeRecovery(address(1), v, r, s);
    }

    function testInitiateRecoveryPostRecoveryFails() public {
        RecoverySpell recovery = testRecoverySpellRotatesAllSigners();

        vm.expectRevert("RecoverySpell: Recovery already initiated");
        recovery.initiateRecovery();
    }

    function testExecuteRecoveryPostRecoveryFails() public {
        RecoverySpell recovery = testRecoverySpellRotatesAllSigners();

        vm.expectRevert(stdError.arithmeticError);
        recovery.executeRecovery(address(1));
    }
}
