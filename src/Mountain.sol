// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISuperfluid, ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {SuperAppBaseCFA} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBaseCFA.sol";
import { IBattleground } from "./interfaces/IBattleground.sol";

import "forge-std/Console.sol";

contract Mountain is SuperAppBaseCFA {

    using SuperTokenV1Library for ISuperToken;

    ISuperToken public immutable streamInToken;
    ISuperToken public immutable streamOutToken;

    int96 public minFlowRate;
    int96 public maxFlowRate;
    uint32 public cooldownPeriodInSeconds;

    address public king;
    uint256 public kingStrength;
    uint256 public kingDefense;
    address public feeCollector;

    IBattleground public immutable battlegroundContract;
    mapping(address => uint256) public cooldowns;

    constructor(
        ISuperToken _streamInToken,
        ISuperToken _streamOutToken,
        int96 _minFlowRate,
        int96 _maxFlowRate,
        uint32 _cooldownPeriodInSeconds,
        address _feeCollector,
        IBattleground _battlegroundContract
    ) SuperAppBaseCFA(ISuperfluid(_streamInToken.getHost()), true, true, true) {

        require(address(_streamOutToken) != address(0), "Zero address not allowed");
        require(_minFlowRate > 0, "Minimum flow rate must be positive");
        require(_maxFlowRate > 0, "Maximum flow rate must be positive");

        streamInToken = _streamInToken;
        streamOutToken = _streamOutToken;

        minFlowRate = _minFlowRate;
        maxFlowRate = _maxFlowRate;

        cooldownPeriodInSeconds = _cooldownPeriodInSeconds;

        king = msg.sender;

        feeCollector = _feeCollector;
        battlegroundContract = _battlegroundContract;
    }

    // how much tax is the king getting
    function kingTaxRate() public view returns (int96){
        return streamInToken.getFlowRate(address(this), king);
    }

    function feeCollectorTaxRate() public view returns (int96){
        return streamInToken.getFlowRate(address(this), feeCollector);
    }

    function stoneFlowRate(address user) public view returns (int96){
        return streamOutToken.getFlowRate(address(this), user);
    }

    // Returns tax rates for king, treasure and fee collector
    function splitAmounts(int96 flowRate) public pure returns (int96 kingAmount, int96 treasureAmount, int96 feeAmount) {
        (kingAmount, treasureAmount, feeAmount) = _calculateTaxes(flowRate);
    }

    // Tax calculation helper function
    function _calculateTaxes(int96 flowRate) internal pure returns(int96 kingTax, int96 treasureTax, int96 feeTax) {
        feeTax = flowRate * 20 / 100; // collector gets 20%
        kingTax = flowRate * 50 / 100; // king gets 50%
        treasureTax = flowRate - feeTax - kingTax; // treasure gets the rest
    }

    // Returns whether the user is in the cooldown period
    function _isInCooldown(address user) internal view returns (bool) {
        return cooldowns[user] + cooldownPeriodInSeconds > block.timestamp;
    }

    // User data decoding
    function _decodeUserData(bytes memory ctx) internal view returns (address nftAddress, uint256 tokenId) {
        bytes memory userData = host.decodeCtx(ctx).userData;
        if(userData.length == 64) {
            (nftAddress, tokenId) = abi.decode(userData, (address, uint256));
        }
    }

    // SuperToken acceptance check
    function isAcceptedSuperToken(ISuperToken superToken) public view override returns (bool) {
        return superToken == streamInToken;
    }
    // Stream creation or update
    function _createOrUpdateSplitStream(address receiver, int96 flowRate, bytes memory ctx) internal returns(bytes memory newCtx) {
        int96 currentFlowRate = streamInToken.getFlowRate(address(this), receiver);
        if (flowRate > 0 && currentFlowRate == 0) {
            return streamInToken.createFlowWithCtx(receiver, flowRate, ctx);
        } else {
            return _updateFlow(receiver, flowRate, currentFlowRate, ctx);
        }
    }

    // Stream update
    function _updateFlow(address receiver, int96 flowRate, int96 currentFlowRate, bytes memory ctx) internal returns(bytes memory newCtx) {
        int96 finalFlowRate = currentFlowRate + flowRate;
        if (finalFlowRate <= 0) {
            return streamInToken.deleteFlowWithCtx(address(this), receiver, ctx);
        } else {
            return streamInToken.updateFlowWithCtx(receiver, finalFlowRate, ctx);
        }
    }

    // Stream deletion or update
    function _deleteOrUpdateSplitStream(address receiver, int96 flowRate, bytes memory ctx) internal returns(bytes memory newCtx) {
        newCtx = ctx;
        int96 currentFlowRate = streamInToken.getFlowRate(address(this), receiver);
        if (currentFlowRate > 0) {
            newCtx = _deleteOrUpdateFlow(receiver, flowRate, currentFlowRate, ctx);
        }
    }

    // Stream deletion or update
    function _deleteOrUpdateFlow(address receiver, int96 flowRate, int96 currentFlowRate, bytes memory ctx) internal returns(bytes memory newCtx) {
        int96 finalFlowRate = currentFlowRate - flowRate;
        if (finalFlowRate <= 0) {
            return streamInToken.deleteFlowWithCtx(address(this), receiver, ctx);
        }
        else {
            return streamInToken.updateFlowWithCtx(receiver, finalFlowRate, ctx);
        }
    }

    function onFlowCreated(
        ISuperToken superToken,
        address sender,
        bytes calldata ctx
    ) internal override returns (bytes memory newCtx) {
        require(!_isInCooldown(sender), "User is in a cooldown period");
        cooldowns[sender] = block.timestamp;
        newCtx = ctx;
        int96 inFLowRate = superToken.getFlowRate(sender, address(this));
        require(inFLowRate >= minFlowRate && inFLowRate <= maxFlowRate, "Flow rate out of range");
        (address nftAddress, uint256 tokenId) = _decodeUserData(ctx);
        if(nftAddress != address(0) && tokenId != 0) {
            // get get how much streamOutToken from random oracle
        }
        //TODO: this is mock until we get the real buff
        int96 outFlowRate = superToken.getFlowRate(sender, address(this));

        newCtx = streamOutToken.createFlowWithCtx(sender, outFlowRate, newCtx);
        (int96 kingTax, int96 treasureTax, int96 feeTax) = _calculateTaxes(outFlowRate);
        newCtx = _createOrUpdateSplitStream(king, kingTax, newCtx);
        newCtx = _createOrUpdateSplitStream(feeCollector, feeTax, newCtx);
    }

    function onFlowUpdated(
        ISuperToken /*superToken*/,
        address /*sender*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory /*newCtx*/) {
        revert("Flow updated not supported");
    }

    function onFlowDeleted(
        ISuperToken superToken,
        address sender,
        address receiver,
        int96 previousFlowRate,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory newCtx) {
        newCtx = ctx;

        // if user stopped receiving streamOutToken don't do anything
        if(superToken == streamOutToken) {
            return newCtx;
        }

        // if user stop sending streamInToken, close the streamOutToken stream if running
        if(superToken == streamInToken) {
            if(streamOutToken.getFlowRate(address(this), sender) != 0) {
               newCtx = streamOutToken.deleteFlowWithCtx(address(this), sender, newCtx);
            }
        }

        // update split values, king and feeCollector based on this change
        (int96 kingTax, , int96 feeTax) = _calculateTaxes(previousFlowRate);
        // adjust (down) stream to king
        newCtx = _deleteOrUpdateSplitStream(king, kingTax, newCtx);
        newCtx = _deleteOrUpdateSplitStream(feeCollector, feeTax, newCtx);

    }
}
