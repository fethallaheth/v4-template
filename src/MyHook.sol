// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * !SECTION
 * assume you launch some token - $TOKEN
 *
 * you setup a uniswap pool for ETH/TOKEN
 *
 * goal is incentivize people to buy TOKEN and also add liquidity to the pool
 *
 * 1. we're gonna issue points to people who buy TOKEN
 * 2. we're gonna issue points to people who add liquidity to the pool
 *
 * the way points work - they'll simply be an ERC-20 token f thier own $POINT
 *
 * we'll simply mint $POINT to people who buy TOKEN or add liquidity to the pool
 *
 * for every 1 eth swapped you get 0.2 of $POINT
 * for every 1 eth added to the pool you get 1 of $POINT
 *
 */
contract MyHook is BaseHook, ERC20 {
    using CurrencyLibrary for Currency;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) ERC20("POINTS", "PNT", 18) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true, // AfterAddLiquidity
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true, // AfterSwap
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        if (key.currency0.isAddressZero()) {
            // 1. we wanna ake sure the swap is happening in a pool that is ETH/Token
            // NOTE: do not revert transaction here
            return (this.afterSwap.selector, int128(delta.amount0()));
        }
        //we only mint points if the swap is happening in a pool that is ETH/Token
        // we only mint points if the swap is Buying TOKEN with ETH
        // if you Sell TOKEN for ETH you do not get points
        if(!swapParams.zeroForOne){
            return (this.afterSwap.selector, 0);
        }
        
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = (ethSpendAmount * 2) / 10; // 0.2 points for every 1 ETH swapped
        _assignPoints(hookData, pointsForSwap);
        return (this.afterSwap.selector, 0);
    }
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata HookData
    )  external override returns (bytes4, BalanceDelta) {
        // 1. we wanna ake sure the swap is happening in a pool that is ETH/Token
        if (!key.currency0.isAddressZero()) {
            // NOTE: do not revert transaction here
            return (this.afterAddLiquidity.selector, delta);
        }

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));

        _assignPoints(HookData, ethSpendAmount);
        return (this.afterAddLiquidity.selector, delta);
    }

    function _assignPoints(bytes calldata hookData, uint256 points) internal {
        if (hookData.length == 0) {
            return;
        }

        address recipient = abi.decode(hookData, (address));

        if (recipient == address(0)) {
            return;
        }

        // Mint points to the recipient
        _mint(recipient, points);
    }
}
