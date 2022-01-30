// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {CERC20} from "./interfaces/CERC20.sol";

/// @notice Get up to date cToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibFuse {
    using FixedPointMathLib for uint256;

    function viewUnderlyingBalanceOf(CERC20 cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulDiv(viewExchangeRate(cToken), 1e18);
    }

    function viewExchangeRate(CERC20 cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (accrualBlockNumberPrior == block.number) return cToken.exchangeRateStored();

        uint256 totalCash = cToken.underlying().balanceOf(address(cToken));
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();
        uint256 adminFeesPrior = cToken.totalAdminFees();
        uint256 fuseFeesPrior = cToken.totalFuseFees();

        uint256 interestAccumulated; // Generated in new scope to avoid stack too deep.
        {
            uint256 borrowRateMantissa = cToken.interestRateModel().getBorrowRate(
                totalCash,
                borrowsPrior,
                reservesPrior + adminFeesPrior + fuseFeesPrior
            );

            require(borrowRateMantissa <= 0.0005e16, "RATE_TOO_HIGH");

            interestAccumulated = (borrowRateMantissa * (block.number - accrualBlockNumberPrior)).mulDiv(
                borrowsPrior,
                1e18
            );
        }

        uint256 totalReserves = cToken.reserveFactorMantissa().mulDiv(interestAccumulated, 1e18) + reservesPrior;
        uint256 totalAdminFees = cToken.adminFeeMantissa().mulDiv(interestAccumulated, 1e18) + adminFeesPrior;
        uint256 totalFuseFees = cToken.fuseFeeMantissa().mulDiv(interestAccumulated, 1e18) + fuseFeesPrior;

        uint256 totalSupply = cToken.totalSupply();

        return
            totalSupply == 0
                ? cToken.initialExchangeRateMantissa()
                : (totalCash + (interestAccumulated + borrowsPrior) - (totalReserves + totalAdminFees + totalFuseFees))
                    .mulDiv(1e18, totalSupply);
    }
}
