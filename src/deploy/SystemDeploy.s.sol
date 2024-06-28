pragma solidity ^0.8.0;

import {MultisigProposal} from
    "@forge-proposal-simulator/src/proposals/MultisigProposal.sol";
import {Addresses} from "@forge-proposal-simulator/addresses/Addresses.sol";

import {Timelock} from "src/Timelock.sol";
import {TimeRestricted} from "src/TimeRestricted.sol";
import {TimelockFactory} from "src/TimelockFactory.sol";
import {InstanceDeployer} from "src/InstanceDeployer.sol";
import {RecoverySpellFactory} from "src/RecoverySpellFactory.sol";

/// @notice system deployment contract
/// all contracts are permissionless
/// DO_PRINT=false DO_BUILD=false DO_RUN=false DO_DEPLOY=true DO_VALIDATE=true forge script src/deploy/SystemDeploy.s.sol:SystemDeploy --fork-url base -vvvvv
contract SystemDeploy is MultisigProposal {
    bytes32 public salt =
        0x0000000000000000000000000000000000000000000000000000000000003afe;

    constructor() {
        addresses = new Addresses("./Addresses.json");
    }

    function name() public pure override returns (string memory) {
        return "SYS_DEPLOY";
    }

    function description() public pure override returns (string memory) {
        return "Deploy TimelockFactory and TimeRestricted contracts";
    }

    function deploy() public override {
        if (!addresses.isAddressSet("TIMELOCK_FACTORY")) {
            TimelockFactory factory = new TimelockFactory{salt: salt}();
            addresses.addAddress("TIMELOCK_FACTORY", address(factory), true);
        }
        if (!addresses.isAddressSet("RECOVERY_SPELL_FACTORY")) {
            RecoverySpellFactory recoveryFactory =
                new RecoverySpellFactory{salt: salt}();
            addresses.addAddress(
                "RECOVERY_SPELL_FACTORY", address(recoveryFactory), true
            );
        }
        if (!addresses.isAddressSet("TIME_RESTRICTED")) {
            TimeRestricted timeRestricted = new TimeRestricted{salt: salt}();
            addresses.addAddress(
                "TIME_RESTRICTED", address(timeRestricted), true
            );
        }
        if (!addresses.isAddressSet("INSTANCE_DEPLOYER")) {
            InstanceDeployer deployer = new InstanceDeployer{salt: salt}(
                addresses.getAddress("SAFE_FACTORY"),
                addresses.getAddress("SAFE_LOGIC"),
                addresses.getAddress("TIMELOCK_FACTORY"),
                addresses.getAddress("TIME_RESTRICTED"),
                addresses.getAddress("MULTICALL3")
            );

            addresses.addAddress("INSTANCE_DEPLOYER", address(deployer), true);
        }
    }

    function validate() public view override {
        if (addresses.isAddressSet("TIMELOCK_FACTORY")) {
            address factory = addresses.getAddress("TIMELOCK_FACTORY");
            assertEq(
                keccak256(factory.code),
                keccak256(type(TimelockFactory).runtimeCode),
                "Incorrect TimelockFactory Bytecode"
            );

            address restricted = addresses.getAddress("TIME_RESTRICTED");
            assertEq(
                keccak256(restricted.code),
                keccak256(type(TimeRestricted).runtimeCode),
                "Incorrect TimeRestricted Bytecode"
            );

            address recoverySpellFactory =
                addresses.getAddress("RECOVERY_SPELL_FACTORY");
            assertEq(
                keccak256(recoverySpellFactory.code),
                keccak256(type(RecoverySpellFactory).runtimeCode),
                "Incorrect RecoverySpellFactory Bytecode"
            );

            /// cannot check bytecode, following error is thrown when trying:
            ///  `"runtimeCode" is not available for contracts containing
            ///   immutable variables.`
            InstanceDeployer deployer =
                InstanceDeployer(addresses.getAddress("INSTANCE_DEPLOYER"));

            assertEq(
                deployer.safeProxyFactory(),
                addresses.getAddress("SAFE_FACTORY"),
                "incorrect safe proxy factory"
            );
            assertEq(
                deployer.safeProxyLogic(),
                addresses.getAddress("SAFE_LOGIC"),
                "incorrect safe logic contract"
            );
            assertEq(
                deployer.timelockFactory(),
                addresses.getAddress("TIMELOCK_FACTORY"),
                "incorrect timelock factory"
            );
            assertEq(
                deployer.timeRestricted(),
                addresses.getAddress("TIME_RESTRICTED"),
                "incorrect TIME_RESTRICTED"
            );
            assertEq(
                deployer.multicall3(),
                addresses.getAddress("MULTICALL3"),
                "incorrect MULTICALL3"
            );
        }
    }
}
