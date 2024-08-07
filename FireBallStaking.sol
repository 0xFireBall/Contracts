// SPDX-License-Identifier: MIT

/*
This smart contract is a staking vault where users can deposit a specific token (referred to as stakedGlp in the contract), in exchange for a vault token (sFIRE). 
The vault token represents the user's share of the staked pool.
The contract also manages reward distribution, where users can earn rewards in a different token (rewardToken, such as USDC) based on their staked balance.
*/

pragma solidity ^0.8.1;

import "../contracts/token/ERC20/ERC20.sol";
import "../contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/security/ReentrancyGuard.sol";
import "../contracts/utils/structs/EnumerableSet.sol";
import "../contracts/utils/Address.sol";
import "../contracts/utils/math/SafeMath.sol";
import "../contracts/access/Ownable.sol";

contract FireRewardVault is ERC20("Staked FIREBALL", "sFIRE"), ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public stakedGlp; // Token that will be staked in this vault
    IERC20 public rewardToken;  // Rewards from Liquidity Wars (USDC)
    uint256 public depositFee = 0; // Fee charged on deposit (in basis points, e.g., 50 = 0.5%)
    uint256 public withdrawFee = 20; // Fee charged on withdrawal (in basis points, e.g., 50 = 0.5%)
    address payable public feeReceiver; // Address that receives the deposit and withdrawal fees

    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateBlock;
    uint256 public totalStaked;

    uint256 public constant REWARD_TOKEN_DECIMALS = 6;  // USDC typically has 6 decimals
    uint256 public constant STAKED_TOKEN_DECIMALS = 18; // sFIRE has 18 decimals

    mapping(address => uint256) public rewards; // Rewards accrued to each user
    mapping(address => uint256) public userRewardPerTokenPaid; // Tracks user's rewardPerTokenPaid
    mapping(address => bool) public whitelisted; // Whitelisted addresses that can call certain owner-only functions

    // Constructor to set initial state variables
    constructor(IERC20 _stakedGlp, address payable _feeReceiver) {
        require(_feeReceiver != address(0), "Fee receiver cannot be zero address");
        stakedGlp = _stakedGlp;
        feeReceiver = _feeReceiver;
    }

    // Treasury can fund the reward pool with reward tokens
    function fundRewardPool(uint256 amount) external onlyOwner onlyWhitelisted {
        require(rewardToken.balanceOf(msg.sender) >= amount, "Insufficient reward balance");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        updateReward(address(0));
        // Adjust for the difference in decimals between reward and staked tokens
        rewardPerTokenStored = rewardPerTokenStored.add(
            amount.mul(10 ** STAKED_TOKEN_DECIMALS).div(totalStaked).div(10 ** REWARD_TOKEN_DECIMALS)
        );
        lastUpdateBlock = block.number;
        emit RewardFunded(amount);
    }

    // Update reward for a user
    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlock = block.number;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    // Calculates the reward per token
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            block.number.sub(lastUpdateBlock).mul(10 ** STAKED_TOKEN_DECIMALS).div(totalStaked)
        );
    }

    // Calculates how much reward a user has earned so far
    function earned(address account) public view returns (uint256) {
        return balanceOf(account)
            .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
            .div(10 ** STAKED_TOKEN_DECIMALS)
            .add(rewards[account]);
    }

    // Users can claim their rewards
    function claimRewards() external {
        updateReward(msg.sender);

        uint256 pendingRewards = rewards[msg.sender];
        require(pendingRewards > 0, "No rewards to claim");

        rewards[msg.sender] = 0;
        require(rewardToken.transfer(msg.sender, pendingRewards), "Reward transfer failed");

        emit RewardClaimed(msg.sender, pendingRewards);
    }

    // Allow users to deposit tokens into the vault
    function deposit(uint256 glpAmount) external nonReentrant {
        require(glpAmount > 0, "Amount must be greater than 0");

        // Update the rewards before proceeding with the deposit
        updateReward(msg.sender);

        uint256 fee = glpAmount.mul(depositFee).div(1000);
        uint256 amountAfterFee = glpAmount.sub(fee);

        stakedGlp.safeTransferFrom(msg.sender, address(this), glpAmount);
        if (fee > 0) {
            stakedGlp.safeTransfer(feeReceiver, fee);
        }

        _mint(msg.sender, amountAfterFee);
        totalStaked = totalStaked.add(amountAfterFee);

        emit Deposit(msg.sender, glpAmount);
    }

    // Allow holders to withdraw their tokens and yield
    function withdraw(uint256 aGlpAmount) public nonReentrant {
        require(balanceOf(msg.sender) >= aGlpAmount, "Not enough aGLP balance");

        // Update the rewards before proceeding with the withdrawal
        updateReward(msg.sender);

        //Calculate glpToReturn
        uint256 glpToReturn = aGlpAmount.mul(stakedGlp.balanceOf(address(this))).div(totalSupply());

        //Burn tokens
        _burn(msg.sender, aGlpAmount);
        totalStaked = totalStaked.sub(aGlpAmount);

        uint256 fee = glpToReturn.mul(withdrawFee).div(1000);
        uint256 amountAfterFee = glpToReturn.sub(fee);

        //Transfer funds
        require(stakedGlp.balanceOf(address(this)) >= amountAfterFee, "Not enough GLP in contract");
        stakedGlp.safeTransfer(msg.sender, amountAfterFee);

        if (fee > 0) {
            stakedGlp.safeTransfer(feeReceiver, fee);
        }

        emit Withdraw(msg.sender, aGlpAmount);
    }

    // Burn fee address
    function setFeeReceiver(address payable _feeReceiver) external onlyOwner onlyWhitelisted {
        require(_feeReceiver != address(0), "Fee receiver cannot be zero address");
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }

    // Allow the Treasury to set the deposit fee
    function setDepositFee(uint256 _depositFee) external onlyOwner onlyWhitelisted {
        depositFee = _depositFee;
    }

    // Allow the Treasury to set the withdrawal fee
    function setWithdrawFee(uint256 _withdrawFee) external onlyOwner onlyWhitelisted {
        withdrawFee = _withdrawFee;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18; // Replace with the correct number of decimals for the underlying token
    }

    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "Not whitelisted");
        _;
    }

    function addWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = true;
        emit WhitelistAdded(_address);
    }

    function removeWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = false;
        emit WhitelistRemoved(_address);
    }

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event FeeReceiverUpdated(address newFeeReceiver);
    event WhitelistAdded(address indexed _address);
    event WhitelistRemoved(address indexed _address);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardFunded(uint256 amount);
}
