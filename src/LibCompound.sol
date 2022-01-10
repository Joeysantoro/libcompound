// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @notice Call a cToken's balanceOfUnderlying() function without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibCompound {
    using FixedPointMathLib for uint256;

    uint256 internal constant borrowRateMaxMantissa = 0.0005e16;

    function viewUnderlyingBalanceOf(CToken cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).fmul(viewExchangeRate(cToken), 1e18);
    }

    function viewExchangeRate(CToken cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (accrualBlockNumberPrior == block.number) cToken.exchangeRateStored();

        uint256 totalCash = cToken.underlying().balanceOf(address(cToken));
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();

        uint256 borrowRateMantissa = cToken.interestRateModel().getBorrowRate(totalCash, borrowsPrior, reservesPrior);

        require(borrowRateMantissa <= borrowRateMaxMantissa, "RATE_TOO_HIGH");

        uint256 interestAccumulated = (borrowRateMantissa * (block.number - accrualBlockNumberPrior)).fmul(
            borrowsPrior,
            1e18
        );

        uint256 totalReserves = cToken.reserveFactorMantissa().fmul(interestAccumulated, 1e18) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = cToken.totalSupply();

        return
            totalSupply == 0
                ? cToken.initialExchangeRateMantissa()
                : (totalCash + totalBorrows + totalReserves).fdiv(totalSupply, 1e18);
    }
}

interface CToken {
    function underlying() external view returns (ERC20);

    function totalSupply() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function accrualBlockNumber() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function interestRateModel() external view returns (InterestRateModel);

    function initialExchangeRateMantissa() external view returns (uint256);
}

interface InterestRateModel {
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);
}
