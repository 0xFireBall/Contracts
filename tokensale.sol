pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenSale is Ownable, ReentrancyGuard {
    IERC20 public tokenForSale;
    IERC20 public usdcToken;
    
    uint256 public constant TOKENS_FOR_SALE = 1_800_000 * 10**18; // 1.8 million tokens
    uint256 public constant PRICE_PER_TOKEN = 20 * 10**4; // 0.20 USDC (assuming 6 decimals for USDC)
    
    uint256 public tokensSold;
    uint256 public tokensBurned;
    uint256 public saleStartTime;
    uint256 public saleDuration;
    
    bool public saleEnded;

    event TokensPurchased(address buyer, uint256 amount);
    event SaleEnded(uint256 tokensSold);

    constructor(address _tokenForSale, address _usdcToken, uint256 _saleDuration) {
        tokenForSale = IERC20(_tokenForSale);
        usdcToken = IERC20(_usdcToken);
        saleDuration = _saleDuration;
    }

    function startSale() external onlyOwner {
        require(saleStartTime == 0, "Sale already started");
        saleStartTime = block.timestamp;
        tokenForSale.transferFrom(msg.sender, address(this), TOKENS_FOR_SALE);
    }

    function buyTokens(uint256 usdcAmount) external nonReentrant {
        require(saleStartTime != 0, "Sale not started");
        require(block.timestamp < saleStartTime + saleDuration, "Sale ended");
        require(!saleEnded, "Sale has ended");

        uint256 requestedTokens = (usdcAmount * 10**18) / PRICE_PER_TOKEN;
        uint256 actualTokensToSend = (requestedTokens * 100) / 99; // Adjusting for 1% burn
        require(requestedTokens > 0, "Not enough USDC sent");
        require(tokensSold + actualTokensToSend <= TOKENS_FOR_SALE, "Not enough tokens left");

        usdcToken.transferFrom(msg.sender, owner(), usdcAmount);
        uint256 balanceBefore = tokenForSale.balanceOf(msg.sender);
        tokenForSale.transfer(msg.sender, actualTokensToSend);
        uint256 actualTokensReceived = tokenForSale.balanceOf(msg.sender) - balanceBefore;

        tokensSold += actualTokensReceived;
        tokensBurned += actualTokensToSend - actualTokensReceived;

        if (tokensSold + tokensBurned >= TOKENS_FOR_SALE) {
            saleEnded = true;
            emit SaleEnded(tokensSold);
        }

        emit TokensPurchased(msg.sender, actualTokensReceived);
    }

    function endSale() external onlyOwner {
        require(saleStartTime != 0, "Sale not started");
        require(!saleEnded, "Sale already ended");
        require(block.timestamp >= saleStartTime + saleDuration, "Sale duration not finished");

        saleEnded = true;
        
        // Transfer any unsold tokens back to the owner
        uint256 unsoldTokens = TOKENS_FOR_SALE - (tokensSold + tokensBurned);
        if (unsoldTokens > 0) {
            tokenForSale.transfer(owner(), unsoldTokens);
        }

        emit SaleEnded(tokensSold);
    }

    function withdrawUnsoldTokens() external onlyOwner {
        require(saleEnded, "Sale not ended");
        uint256 unsoldTokens = tokenForSale.balanceOf(address(this));
        if (unsoldTokens > 0) {
            tokenForSale.transfer(owner(), unsoldTokens);
        }
    }
}
