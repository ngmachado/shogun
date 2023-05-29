// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {SuperAppBaseCFA} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBaseCFA.sol";
import { IBattleground } from "./interfaces/IBattleground.sol";

contract Mountain is SuperAppBaseCFA {

    error NoUpdateAllowed();
    error ZeroAddress();
    error NoSelfAttack();

    // ---------------------------------------------------------------------------------------------
    // EVENTS
    event HailNewKing(address king, uint256 army);
    event BuildingArmy(address account, int96 armyFlowRate);

    /// @notice Importing the SuperToken Library to make working with streams easy.
    using SuperTokenV1Library for ISuperToken;
    // ---------------------------------------------------------------------------------------------
    // STORAGE & IMMUTABLES

    /// @notice Token coming in and token going out
    ISuperToken public immutable streamInToken;
    ISuperToken public immutable streamOutToken;

    /// @notice the last time the rate changed
    uint256 public immutable initialTime;
    int96 public immutable initialRate;

    /// @notice the amount of tax which remains in the contract as treasure
    int96 public immutable treasureRate;

    /// @notice the step in the army auction. How much bigger than previous should it be?
    uint256 public step;

    /// @notice the current king of the hill
    address public king;
    uint256 public kingStrength;
    uint256 public kingDefense;

    /// @notice the fee collector
    address public feeCollector;

    // battleground contract
    IBattleground public immutable battlegroundContract;

    constructor(
        ISuperToken _streamInToken,
        ISuperToken _streamOutToken,
        uint256 _step,
        int96 _initialRate,
        int96 _treasureRate,
        address _feeCollector,
        IBattleground _battlegroundContract
    ) SuperAppBaseCFA(
        ISuperfluid(_streamInToken.getHost()),
        true, true, true
    ) {
        // TODO: add checks for _streamInToken, _streamOutToken
        // streamInToken is test it by getting host address
        if(address(_streamOutToken) == address(0)) revert ZeroAddress();

        streamInToken = _streamInToken;
        streamOutToken = _streamOutToken;

        initialRate = _initialRate;
        step = _step;
        initialTime = block.timestamp;
        king = msg.sender;
        treasureRate = _treasureRate;

        feeCollector = _feeCollector;
        battlegroundContract = _battlegroundContract;
    }

    // ---------------------------------------------------------------------------------------------
    // UTILITY FUNCTIONS
    // ---------------------------------------------------------------------------------------------

    function taxRate() public view returns (int96){
        return streamInToken.getFlowRate(address(this), king);
    }

    //TODO: review
    function _rate() internal view returns (int96) {
        int96 calculatedRate = initialRate - int96(int256(block.timestamp - initialTime));
        return calculatedRate < 0 ? int96(0) : calculatedRate;
    }

    function rate() public view returns (int96) {
        return _rate();
    }

    function rate(address user) public view returns (int96) {
        return streamOutToken.getFlowRate(address(this), user) / streamInToken.getFlowRate(user, address(this));
    }

    function _armyFlowRate(int96 cashFlowRate) internal view returns (int96) {
        uint256 _cashFlowRate = uint96(cashFlowRate);
        uint256 _rate = uint96(_rate());
        uint256 armyFlowRate = uint256(_cashFlowRate * _rate) / 1e18;
        require(armyFlowRate <= uint256(uint96(type(int96).max)), "armyFlowRate overflow");
        return int96(int256(armyFlowRate));
    }

    function armyFlowRate(int96 cashFlowRate) public view returns (int96) {
        return _armyFlowRate(cashFlowRate);
    }

    //TODO: review
    function _totalTaxMinusFee() internal view returns (int96){
        int96 totalInflow = streamInToken.getNetFlowRate(address(this)) + streamInToken.getFlowRate(address(this), king);
        return totalInflow - (totalInflow * treasureRate / 10000); // treasureRate defines the amount kept in contract
    }

    // ---------------------------------------------------------------------------------------------
    // BECOMING KING
    // ---------------------------------------------------------------------------------------------

    function attack() public {
        // king can't attack himself
        if(msg.sender == king) revert NoSelfAttack();
        // check battleground for army
        (uint256 totalStrength, uint256 totalDefense) = battlegroundContract.getUserArmyStats(msg.sender);

        //TODO: Add random buffer here

        if(totalStrength + totalDefense > kingStrength + kingDefense) {
           // _becomeKing(msg.sender, totalStrength, totalDefense);
        } else {
            // TODO: how much should the army lose?
            battlegroundContract.armyFlee(msg.sender, 20);
        }
    }

    function isAcceptedSuperToken(ISuperToken superToken) public view override returns (bool) {
        return superToken == streamInToken;
    }

    // ---------------------------------------------------------------------------------------------
    // SUPER APP CALLBACKS
    // ---------------------------------------------------------------------------------------------

    /// @dev super app callback triggered after user sends stream to contract
    function onFlowCreated(
        ISuperToken superToken,
        address sender,
        bytes calldata ctx
    ) internal override returns (bytes memory newCtx) {
        newCtx = ctx;
        // user is streaming in streamInToken, send him back streamOutToken.
        // if _armyFlowRate returns zero we want to revert the operation.
        int96 armyFlowRate = _armyFlowRate(superToken.getFlowRate(sender, address(this)));
        newCtx = streamOutToken.createFlowWithCtx(sender, armyFlowRate, ctx);
        // adjust (up) stream to king
        streamInToken.getFlowRate(address(this), king) == 0
            ? newCtx = streamInToken.createFlowWithCtx(king, _totalTaxMinusFee(), newCtx)
            : newCtx = streamInToken.updateFlowWithCtx(king, _totalTaxMinusFee(), newCtx);
        emit BuildingArmy(sender, armyFlowRate);
    }

    function onFlowUpdated(
        ISuperToken /*superToken*/,
        address /*sender*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory /*newCtx*/) {
        revert NoUpdateAllowed();
    }

    function onFlowDeleted(
        ISuperToken /*superToken*/,
        address sender,
        address /*receiver*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory newCtx) {
        newCtx = ctx;
        // user stopped streaming in streamInToken, close the streamOutToken stream if running
        if(streamOutToken.getFlowRate(address(this), sender) != 0) {
            newCtx = streamOutToken.deleteFlowWithCtx(address(this), sender, newCtx);
        }
        // only operate on stream if they are running
        if(streamInToken.getFlowRate(address(this), king) != 0) {
            // adjust (down) stream to king
            int96 _taxRate = _totalTaxMinusFee();
            _taxRate == 0
                ? newCtx = streamInToken.deleteFlowWithCtx(address(this), king, newCtx)
                : newCtx = streamInToken.updateFlowWithCtx(king, _taxRate, newCtx);
        }
    }
}
