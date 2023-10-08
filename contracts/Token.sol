// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// File contracts/Token.sol
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Token is ERC20Burnable, Ownable {
    // ADDRESSESS -------------------------------------------------------------------------------------------
    address public lpPair; // Liquidity token address
    address public treasuryAddress; // owner fee wallet address

    // VALUES -----------------------------------------------------------------------------------------------
    uint256 public swapThreshold; // swap tokens limit
    uint256 public constant TAX_DIVISOR = 10000; // divisor | 0.0001 max presition fee

    // BOOLEANS ---------------------------------------------------------------------------------------------
    bool public inSwap; // used for dont take fee on swaps

    // MAPPINGS ---------------------------------------------------------------------------------------------
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) public _isExcludedFromFee; // list of users excluded from fee

    // STRUCTS ----------------------------------------------------------------------------------------------
    struct Fees {
        uint16 buyFee; // fee when people BUY tokens
        uint16 sellFee; // fee when people SELL tokens
        uint16 transferFee; // fee when people TRANSFER tokens
    }

    // OBJECTS ----------------------------------------------------------------------------------------------
    address public router;
    Fees public _feesRates; // fees rates

    // MODIFIERS --------------------------------------------------------------------------------------------
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // CONSTRUCTOR ------------------------------------------------------------------------------------------
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 supply,
        address[] memory addresses, // routerAddress, treasuryAddress
        uint16[] memory percents //buyFee, sellFee
    ) ERC20(tokenName, tokenSymbol) {
        require(addresses.length == 2, "Invalid address argument");
        require(percents.length == 2, "Invalid percent argument");
        require(percents[0] <= 9900 && percents[1] <= 9900, "Too hight tax");

        // super.transferOwnership(tokenOwner);
        treasuryAddress = addresses[1];

        _mint(msg.sender, supply);

        // default fees
        _feesRates = Fees({
            buyFee: percents[0],
            sellFee: percents[1],
            transferFee: 0
        });

        router = addresses[0];

        // Create a uniswap pair for this new token
        (bool success, bytes memory data) = factory().call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("createPair(address,address)"))),
                address(this),
                WETH()
            )
        );
        lpPair = abi.decode(data, (address));

        automatedMarketMakerPairs[lpPair] = true;

        // exclude from fees
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[treasuryAddress] = true;
        _isExcludedFromFee[address(this)] = true;

        // contract do swap when have 1k tokens balance
        swapThreshold = 1000 ether;
    }

    // To receive BNB from dexRouter when swapping
    receive() external payable {}

    // Set fees
    function setTaxes(
        uint16 buyFee,
        uint16 sellFee,
        uint16 transferFee
    ) external virtual onlyOwner {
        require(buyFee <= 9900 && sellFee <= 9900, "Too hight tax");
        _feesRates.buyFee = buyFee;
        _feesRates.sellFee = sellFee;
        _feesRates.transferFee = transferFee;
    }

    function setSwapThreshold(uint256 value) public virtual onlyOwner {
        swapThreshold = value;
    }

    function setTreasuryAddress(
        address _treasuryAddress
    ) public virtual onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    // this function will be called every buy, sell or transfer
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (inSwap) {
            super._transfer(from, to, amount);
            return;
        }

        // if we have more than swapThreshold tokens
        uint256 contractTokenBalance = balanceOf(address(this));
        if (
            contractTokenBalance >= swapThreshold &&
            !inSwap &&
            from != lpPair &&
            balanceOf(lpPair) > 0 &&
            !_isExcludedFromFee[to] &&
            !_isExcludedFromFee[from]
        ) {
            swapTokensForNative(contractTokenBalance, treasuryAddress);
        }

        _finalizeTransfer(from, to, amount);
    }

    function WETH() public virtual returns (address) {
        (bool success, bytes memory data) = router.staticcall(
            abi.encodeWithSelector(bytes4(keccak256(bytes("WETH()"))))
        );
        return abi.decode(data, (address));
    }

    function factory() public virtual returns (address) {
        (bool success, bytes memory data) = router.staticcall(
            abi.encodeWithSelector(bytes4(keccak256(bytes("factory()"))))
        );
        return abi.decode(data, (address));
    }

    function swapTokensForNative(uint256 amount, address to) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH();

        _approve(address(this), router, amount);

        (bool success, ) = router.call(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        bytes(
                            "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)"
                        )
                    )
                ),
                amount,
                0,
                path,
                to,
                block.timestamp + 20000
            )
        );
        require(success, "Error: swapTokensForNative");
    }

    function _finalizeTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        // by default receiver receive 100% of sended amount
        uint256 amountReceived = amount;

        // If takeFee is false there is 0% fee
        bool takeFee = true;
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        // check if we need take fee or not
        if (takeFee) {
            // if we need take fee
            // calc how much we need take
            uint256 feeAmount = calcBuySellTransferFee(from, to, amount);

            if (feeAmount > 0) {
                // and transfer fee to contract
                super._transfer(from, address(this), feeAmount);
            }
        }

        // finally send remaining tokens to recipient
        super._transfer(from, to, amountReceived);
    }

    function calcBuySellTransferFee(
        address from,
        address to,
        uint256 amount
    ) internal view virtual returns (uint256) {
        // by default we take zero fee
        uint256 feePercent = 0;
        uint256 feeAmount = 0;

        // BUY -> FROM == LP ADDRESS
        if (automatedMarketMakerPairs[from]) {
            feePercent += _feesRates.buyFee;
        }
        // SELL -> TO == LP ADDRESS
        else if (automatedMarketMakerPairs[to]) {
            feePercent += _feesRates.sellFee;
        }
        // TRANSFER
        else {
            feePercent += _feesRates.transferFee;
        }

        // CALC FEES AMOUT
        if (feePercent > 0) {
            feeAmount = (amount * feePercent) / TAX_DIVISOR;
        }

        return feeAmount;
    }

    function excludeFromFee(
        address account,
        bool val
    ) public virtual onlyOwner {
        _isExcludedFromFee[account] = val;
    }

    function renounceOwnership() public virtual override onlyOwner {
        require(
            _feesRates.buyFee < 4500 && _feesRates.sellFee < 4500,
            "Too hight tax, can't renounce ownership."
        );
        _transferOwnership(address(0));
    }
}
