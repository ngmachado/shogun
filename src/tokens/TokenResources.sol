// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC1155PresetMinterPauser } from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";

contract TokenResources is ERC1155PresetMinterPauser {

    uint256 public constant STONE_ID_1 = 0;
    uint256 public constant STONE_ID_2 = 1;
    uint256 public constant STONE_ID_3 = 2;
    uint256 public constant STONE_ID_4 = 3;
    uint256 public constant STONE_ID_5 = 4;

	constructor() ERC1155PresetMinterPauser("shogun-stones")  {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		// Stones
		_mint(_msgSender(), STONE_ID_1, 1000000 ether, "");
		_mint(_msgSender(), STONE_ID_2, 1000000 ether, "");
		_mint(_msgSender(), STONE_ID_3, 1000000 ether, "");
		_mint(_msgSender(), STONE_ID_4, 1000000 ether, "");
		_mint(_msgSender(), STONE_ID_5, 1000000 ether, "");
	}
}
