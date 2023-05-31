// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC1155PresetMinterPauser } from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TokenResources is ERC1155PresetMinterPauser {

	event SwapTokens(address indexed player, address indexed stoneTokenAddress, uint256 indexed tokenId, uint256 amount);
	event SetArmyUnitTypeChanged(uint256 indexed tokenId, address indexed stoneTokenAddress, uint16 exchangeRate, uint32 attackPowerUnit, uint32 defensePowerUnit);

	struct ArmyUnitType {
		uint16 stoneToArmyExchangeRate;
		address stoneTokenAddress;
		uint32 attackPowerUnit;
		uint32 defensePowerUnit;
	}

	uint256 public lastTokenId;

	// mapping from token ID to corresponding ArmyUnitType
	mapping(uint256 => ArmyUnitType) public tokenIdToArmyUnit;

	// initializes army unit types
	constructor(address admin, ArmyUnitType[] memory army) ERC1155PresetMinterPauser("armyToken.local") {
		_setupRole(DEFAULT_ADMIN_ROLE, admin);
		require(army.length > 0, "army length must be greater than 0");
		lastTokenId = army.length;
		for(uint256 i = 0; i < army.length; i++) {
			setArmyUnit(i+1, army[i]);
		}
	}

	// swap stones for army units
	function swapTokens(uint256 tokenId, uint256 amount) public {
		ArmyUnitType memory armyUnit = tokenIdToArmyUnit[tokenId];
		require(armyUnit.stoneTokenAddress != address(0), "Invalid stone token address");
		require(amount > 0 && amount % (1 ether) == 0, "Amount must represent whole tokens");
		require(armyUnit.stoneToArmyExchangeRate != 0, "Invalid exchange rate");
		require(IERC20(armyUnit.stoneTokenAddress).transferFrom(_msgSender(), address(this), amount), "Transfer failed");
		_mint(_msgSender(), tokenId, amount * armyUnit.stoneToArmyExchangeRate, "");
	}

	// batch swap tokens
	function batchSwapTokens(uint256[] memory tokenIds, uint256[] memory amounts) public {
		require(tokenIds.length == amounts.length, "tokenIds and amounts must have the same length");
		for(uint256 i = 0; i < tokenIds.length; i++) {
			swapTokens(tokenIds[i], amounts[i]);
		}
	}

	// Set army unit type for given token ID
	function setArmyUnit(uint256 tokenId, ArmyUnitType memory armyUnit ) public {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not an admin");
		require(isValidArmyUnit(armyUnit), "Invalid army unit");
		tokenIdToArmyUnit[tokenId] = armyUnit;
		if(tokenId > lastTokenId) {
			lastTokenId = tokenId;
		}
		emit SetArmyUnitTypeChanged(tokenId, armyUnit.stoneTokenAddress, armyUnit.stoneToArmyExchangeRate, armyUnit.attackPowerUnit, armyUnit.defensePowerUnit);
	}

	// Helper function to check if an army unit type is valid
	function isValidArmyUnit(ArmyUnitType memory armyUnit) internal pure returns (bool) {
		return (
			armyUnit.stoneToArmyExchangeRate != 0 &&
			armyUnit.stoneTokenAddress != address(0) &&
			armyUnit.attackPowerUnit != 0 &&
			armyUnit.defensePowerUnit != 0
		);
	}

	// Return the total attack power and defense power for all army units
	function getTotalArmyUnits() public view returns (uint256 totalAttackPower, uint256 totalDefensePower) {
		for(uint256 i = 1; i <= lastTokenId; i++) {
			ArmyUnitType memory armyUnit = tokenIdToArmyUnit[i];
			totalAttackPower += armyUnit.attackPowerUnit * balanceOf(_msgSender(), i);
			totalDefensePower += armyUnit.defensePowerUnit * balanceOf(_msgSender(), i);
		}
	}

	// Get an army unit type by token ID
	function getArmyUnit(uint256 tokenId) public view returns (ArmyUnitType memory) {
		return tokenIdToArmyUnit[tokenId];
	}
}