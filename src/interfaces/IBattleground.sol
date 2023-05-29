// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

interface IBattleground {
	function assembleArmy(address[] memory tokens, uint256[] memory amountsInWei) external;
	function disbandArmy() external;
	function getUserArmyStats(address user) external view returns (uint256 totalStrength, uint256 totalDefense);
	function armyFlee(address user, uint256 percentageOfBurn) external;
}