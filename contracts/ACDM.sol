// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./AcademyToken.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "hardhat/console.sol";

contract Token is AccessControl {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    AcademyToken token;

    uint256 multiplier = 1 ether;
    uint256 round = 0;
    uint256 roundTime = 3 days;
    uint256 tokenInitialPrice = 0.00001 ether; // 0,00001 eth

    mapping(uint256 => SaleRoundSettings) public saleRounds;
    mapping(uint256 => TradeRoundSettings) public tradeRounds;
    mapping(address => address[]) public referrals;
    mapping(address => address) public registrations;

    Bid[] bids;

    struct Bid {
        address seller;
        uint256 amount; // tokens amount
        uint256 price; // eth
    }

    struct SaleRoundSettings {
        uint256 maxTradeAmount; // ETH max trade amount
        uint256 tradeAmount; // ETH trade amount
        uint256 tokenPrice; // ACDM token
        uint256 tokensAmount;
        uint256 startTime;
        bool isActive;
    }

    struct TradeRoundSettings {
        uint256 tradeAmount; // ETH trade amount
        uint256 startTime;
        bool isActive;
    }

    event BidCanceled(address _msgSender, uint256 index);
    event BidClosed(address _msgSender);
    event AllBidsCanceled(address _msgSender);
    event BidCreated(address _msgSender, uint256 _amount, uint256 _price);
    event Trade(
        address _msgSender,
        address _seller,
        uint256 _amount,
        uint256 _price
    );
    event BuyToken(address _msgSender, uint256 _amount, uint256 _price);

    modifier isActiveRound() {
        require(
            saleRounds[round].startTime + roundTime < block.timestamp,
            "Marketplace: Sale round is over"
        );
        _;
    }

    modifier isActiveTradeRound() {
        require(
            tradeRounds[round].isActive,
            "Marketplace: Trade round is not started yet"
        );
        _;
    }

    modifier isAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Marketplace: You are not an admin"
        );
        _;
    }

    constructor(address _tokenAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        token = AcademyToken(_tokenAddress);

        saleRounds[round].tokenPrice = tokenInitialPrice;
        saleRounds[round].maxTradeAmount = 1 ether;
        saleRounds[round].isActive = false;
        saleRounds[round].tradeAmount = 0;
        saleRounds[round].startTime = block.timestamp;
        saleRounds[round].tokensAmount =
            saleRounds[round].maxTradeAmount /
            saleRounds[round].tokenPrice;
    }

    // Registration 

    function registration(address _referral) external {
        console.log(_referral, msg.sender);
        require(
            _referral != address(0),
            "Marketplace: Referral can't be a zero address"
        );

        require(
            _referral != msg.sender,
            "Marketplace: You can't choose yourself as a referral"
        );

        require(
            referrals[_referral].length != 2,
            "Marketplace: User can only have two referrals"
        );

        registrations[msg.sender] = _referral;
        referrals[_referral].push(msg.sender);
    }

    // Sale Round 

    function startSaleRound() external isAdmin {
        if (round > 0) {
            setupNewSaleRound();
        }

        SaleRoundSettings storage settings = saleRounds[round];
        settings.isActive = true;

        token.mint(address(this), settings.tokensAmount);
    }

    function endSaleRound() public isAdmin {
        if (!isFullfilledMaxTrade()) {
            require(
                !isSaleRoundTimeIsOver(),
                "Martketplace: Sale round time is not finished yet"
            );
        }

        saleRounds[round].isActive = false;

        burnUnredeemedTokens();
        startTradeRound();
    }

    function burnUnredeemedTokens() internal {
        uint256 burnAmount = saleRounds[round].tokensAmount -
            convertEthToTokens(saleRounds[round].tradeAmount);

        console.log(
            convertEthToTokens(saleRounds[round].tradeAmount),
            saleRounds[round].tradeAmount,
            saleRounds[round].tokensAmount,
            burnAmount
        );
        uint256 balance = token.balanceOf(address(this));
        console.log(balance);

        if (burnAmount > 0) {
            token.burn(address(this), burnAmount);
        }
    }

    function setupNewSaleRound() internal {
        SaleRoundSettings storage prevSaleRound = saleRounds[round - 1];
        TradeRoundSettings storage prevTradeRound = tradeRounds[round - 1];

        saleRounds[round].tokenPrice = getNextRoundTokenPrice(
            (prevSaleRound.tokenPrice)
        );
        saleRounds[round].maxTradeAmount = prevTradeRound.tradeAmount;
        saleRounds[round].isActive = false;
        saleRounds[round].tradeAmount = 0;
        saleRounds[round].tokensAmount =
            saleRounds[round].maxTradeAmount /
            saleRounds[round].tokenPrice;

        console.log(
            "setupNewSaleRound",
            getNextRoundTokenPrice((prevSaleRound.tokenPrice)),
            saleRounds[round].tokensAmount,
            saleRounds[round].maxTradeAmount
        );
    }

    function buyOnSaleRound() external payable {
        SaleRoundSettings storage settings = saleRounds[round];

        uint256 amount = msg.value;

        require(
            settings.tradeAmount + amount <= settings.maxTradeAmount,
            "Marketplace: The token purchase limit for this round has been reached"
        );

        settings.tradeAmount += amount;

        uint256 tokensAmount = convertEthToTokens(amount);

        uint256 leftAfterDestribution = destributeTreasureForSale(
            msg.sender,
            tokensAmount
        );

        token.transfer(msg.sender, leftAfterDestribution);

        emit BuyToken(msg.sender, tokensAmount, settings.tokenPrice);
    }

    function destributeTreasureForSale(address _msgSender, uint256 _amount)
        internal
        returns (uint256)
    {
        address referral = registrations[_msgSender];
        uint256 leftAfterDestribution = _amount;
        uint256 firstReferralTreasure = _amount - ((_amount / 100) * 95);
        uint256 secondReferralTreasure = _amount - ((_amount / 100) * 97);

        if (referrals[referral].length == 1) {
            token.transfer(referrals[referral][0], firstReferralTreasure);
            leftAfterDestribution -= firstReferralTreasure;
        }

        if (referrals[referral].length == 2) {
            token.transfer(referrals[referral][1], secondReferralTreasure);
            leftAfterDestribution -= secondReferralTreasure;
        }

        return leftAfterDestribution;
    }

    // Trade Round

    function trade(uint256 _index, uint256 _amount)
        external
        payable
        isActiveTradeRound
    {
        Bid storage bid = bids[_index];

        uint256 ethCost = convertTokensToEth(_amount, bid.price);

        require(
            bid.amount >= _amount,
            "Marketplace: You can't buy more tokens than bid specified"
        );

        bid.amount -= _amount;

        require(token.transfer(msg.sender, _amount));

        require(msg.value == ethCost, "Marketplace: You don't have enough eth");

        address referral = registrations[msg.sender];
        uint256 leftAfterDestribution = msg.value;
        uint256 firstReferralTreasure = msg.value - ((msg.value / 1000) * 975);
        uint256 secondReferralTreasure = msg.value - ((msg.value / 1000) * 975);

        payable(bid.seller).transfer(leftAfterDestribution);

        if (bid.amount == _amount) {
            closeBid(_index);
        }

        tradeRounds[round].tradeAmount += ethCost;

        console.log("trade", ethCost, tradeRounds[round].tradeAmount, round);

        emit Trade(msg.sender, bid.seller, _amount, bid.price);
    }

    function startTradeRound() internal {
        TradeRoundSettings storage settings = tradeRounds[round];

        settings.tradeAmount = 0;
        settings.isActive = true;
    }

    function endTradeRound() external isAdmin {
        if (bids.length > 0) {
            cancelAllBids();
        }
        round++;
    }

    function destributeTreasureForTrade(address _msgSender)
        public
        payable
        isAdmin
        returns (uint256)
    {
        uint256 _amount = msg.value;

        address referral = registrations[_msgSender];
        uint256 leftAfterDestribution = _amount;
        uint256 firstReferralTreasure = _amount - ((_amount / 1000) * 975);
        uint256 secondReferralTreasure = _amount - ((_amount / 1000) * 975);

        if (referrals[referral].length == 1) {
            payable(referrals[referral][0]).transfer(firstReferralTreasure);
            leftAfterDestribution -= firstReferralTreasure;
        }

        if (referrals[referral].length == 2) {
            payable(referrals[referral][1]).transfer(secondReferralTreasure);
            leftAfterDestribution -= secondReferralTreasure;
        }

        if (referrals[referral].length == 0) {
            payable(address(this)).transfer(
                firstReferralTreasure + secondReferralTreasure
            );
            leftAfterDestribution -=
                firstReferralTreasure -
                secondReferralTreasure;
        }
        return leftAfterDestribution;
    }
