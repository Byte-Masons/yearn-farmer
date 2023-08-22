// SPDX-License-Identifier: GNU AGPLv3

pragma solidity ^0.8.0;

interface IYearnVault {
    /**
     * @dev The underlying token (want) of the Yearn vault
     */
    function token() external view returns (address);

    /**
     * @dev Deposit in to the vault for _amount
     */
    function deposit(uint256 _amount) external;

    /**
     * @dev Withdraw _maxShares from the vault
     */
    function withdraw(uint256 _maxShares) external;

    /**
     * @dev Withdraw all from the vault
     */
    function withdraw() external;

    /**
     * @dev The amount of vault shares held by _holder
     */
    function balanceOf(address _holder) external view returns (uint256);

    /**
     * @dev The price in token/want for a vault share
     */
    function pricePerShare() external view returns (uint256);

    /**
     * @dev Increases the allowance of the vault token for _spender
     */
    function increaseAllowance(address _spender, uint256 _amount) external;
}
