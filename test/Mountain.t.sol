// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { Mountain } from "./../src/Mountain.sol";
import {IBattleground} from "./../src/interfaces/IBattleground.sol";

import {
SuperfluidFrameworkDeployer, ISuperToken, ISuperfluid
} from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";

import {
SuperTokenDeployer, TestToken, SuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperTokenDeployer.sol";
import { ISuperApp } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperApp.sol";
import { IPureSuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/IPureSuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";

contract MountainTest is Test {

	using SuperTokenV1Library for IPureSuperToken;

	uint256 constant INT256_MAX_AS_UINT256 = uint256(type(int256).max);

	address public owner = address(0x01);
	address public feeCollector = address(0x02);

	address public player1 = address(0x11);
	address public player2 = address(0x12);
	address public player3 = address(0x13);
	address public player4 = address(0x14);

	Mountain public mountain;
	IBattleground public bg;

	SuperfluidFrameworkDeployer public sfDeployer;
	SuperfluidFrameworkDeployer.Framework public sf;

	IPureSuperToken public streamInToken;
	IPureSuperToken public streamOutToken;

	function setUp() public virtual {
		vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
		// get UINT256_MAX
		vm.startPrank(owner);
		//mountain = new Mountain();

		sfDeployer = new SuperfluidFrameworkDeployer();
		sf = sfDeployer.getFramework();

		SuperTokenDeployer tokenDeployer = new SuperTokenDeployer(address(sf.superTokenFactory), address(sf.resolver));
		sf.resolver.addAdmin(address(tokenDeployer));
		// create a new super token
		streamInToken = tokenDeployer.deployPureSuperToken("TokenIn", "IN", INT256_MAX_AS_UINT256);
		streamOutToken = tokenDeployer.deployPureSuperToken("TokenOut", "OUT", INT256_MAX_AS_UINT256);

		// deploy battleground
		bg = IBattleground(address(0));

		// deploy mountain
		mountain = new Mountain(
			streamInToken,
			streamOutToken,
			10000000000,
			1 ether,
			1000,
			feeCollector,
			IBattleground(address(0))
		);

		// transfer streamOutToken to mountain
		streamOutToken.transfer(address(mountain), INT256_MAX_AS_UINT256);

	}

	// Helper functions

	function __checkIfNotJailed() private {
		assertEq(sf.host.isAppJailed(ISuperApp(mountain)), false, "mountain is jailed");
	}

	function __checkStreams(address sender) private {
		// check if sender is streaming to mountain
		(, int96 inFlowRate , , ) = streamInToken.getFlowInfo(sender, address(mountain));
		assertEq(inFlowRate, 1 ether, "wrong inFlowRate");
		// check if mountain is streaming to sender
		(, int96 outFlowRate , , ) = streamOutToken.getFlowInfo(address(mountain), sender);
		assertEq(outFlowRate, 1 ether, "wrong outFlowRate");
	}


	// test mountain constructor
	function testDeployment() public {
		assertEq(address(mountain.streamInToken()), address(streamInToken), "wrong streamInToken");
		assertEq(address(mountain.streamOutToken()), address(streamOutToken), "wrong streamOutToken");
		assertEq(mountain.step(), 10000000000, "wrong step");
		assertEq(mountain.initialRate(), 1 ether, "wrong initialRate");
		assertEq(mountain.treasureRate(), 1000, "wrong treasureRate");
		assertEq(address(mountain.feeCollector()), feeCollector, "wrong feeCollector");
		assertEq(address(mountain.battlegroundContract()), address(bg), "wrong battlegroundContract");
		__checkIfNotJailed();
	}

	// check if streamInToken is allowed
	function testStreamInTokenApproved() public {
		assertEq(mountain.isAcceptedSuperToken(streamInToken), true, "wrong isAcceptedSuperToken");
	}

	// test if mountain is superApp
	function testIsSuperApp() public {
		assertEq(sf.host.isApp(ISuperApp(mountain)), true, "wrong isSuperApp");
		__checkIfNotJailed();
	}

	// player 1 streams to mountain
	function testStreamToMountain() public {
		vm.startPrank(owner);
		// transfer tokens to player 1
		streamInToken.transfer(player1, 10000000 ether);
		vm.stopPrank();

		// check if player1 has tokens
		uint256 balance = streamInToken.balanceOf(player1);
		assertEq(balance, 10000000 ether, "wrong balance");
		vm.startPrank(player1);
		streamInToken.createFlow(address(mountain), 1 ether);
		__checkStreams(player1);
		__checkIfNotJailed();
	}

}
