// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/OptionNFT.sol";
import "./lib/VIP.sol";

contract StakingNFT is Pausable, Ownable, StakingOptionsNFT, VipOptions,ReentrancyGuard {

    struct userInfoStaking {
        bool isActive;
        uint256 vipMember;
        uint256 tokenId;
        uint256 startTime;
        uint256 endTime;
        uint256 stakeOptions;
        uint256 fullLockedDays;
        uint256 reward;
    }

    struct userInfoTotal{
        uint256 totalUserStaked; 
        uint256 totalUserReward;
        uint256 totalUserRewardClaimed;
    }

    struct userInfoVip{
        bool isVip;
        uint256 vipMember;
    }

    ERC20 public token;
    ERC20 public tokenRR;
    mapping(bytes32 => userInfoStaking) private infoStaking;
    mapping(address => userInfoTotal) private infoTotal;
    mapping(address => userInfoVip) public infoVipUser;
    mapping(address => bool) public erc721Whitelist;
    mapping(address => uint256) public countStakeNFT;
    
    event Erc721WhitelistUpdated(address[] erc721s, bool status);
    event UserBuyVip(address indexed user,uint256 indexed vip);
    event UsersStaking(address indexed user, uint256 amountStake, uint256 indexed option, uint256 id, address erc721);
    event UserUnstaking(address indexed user, uint256 claimableAmountStake, uint256 indexed option, uint256 indexed id,address erc721);
    event UserReward(address indexed user, uint256 claimableReward, uint256 indexed option, uint256 indexed id);

    uint256 public totalStaked = 0;
    uint256 public totalClaimedReward = 0;
    uint256 public totalAccumulatedRewardsReleased = 0;

    constructor(ERC20 _token, ERC20 _tokenRR) 
    {
        token = _token;
        tokenRR = _tokenRR;
    }

    function updateErc721Whitelist(address[] memory erc721s, bool status)
        public
        onlyOwner
    {
        uint256 length = erc721s.length;

        require(length > 0, "NftMarket: erc721 list is required");

        for (uint256 i = 0; i < length; i++) {
            erc721Whitelist[erc721s[i]] = status;
        }

        emit Erc721WhitelistUpdated(erc721s, status);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function buyVip(uint256 _vip) public whenNotPaused nonReentrant {
        require(infoVipList[_vip].endTime >= block.timestamp, "Vip is not available");
        require(infoVipUser[msg.sender].vipMember != _vip, "Vip: You are at this vip");
        require(infoVipUser[msg.sender].vipMember < _vip, "Vip: You are on a higher level than this level");
        uint256 _amount = infoVipList[_vip].price;

        token.transferFrom(msg.sender, address(this), _amount);

        if (infoVipUser[msg.sender].isVip == false) {
            infoVipUser[msg.sender].isVip = true;
            infoVipUser[msg.sender].vipMember = _vip;
        }
        else {
            infoVipUser[msg.sender].vipMember = _vip;
        }
        emit UserBuyVip(msg.sender, _vip);
        vipInfo storage info = infoVipList[_vip];
        info.countedAmount+=1;
    }

    function userStake(uint256 _tokenId, uint256 _ops, uint256 _id, address _erc721) public whenNotPaused nonReentrant {
        require(erc721Whitelist[_erc721] == true,"ContractNFT is not in whitelist");
        bytes32 _value = keccak256(abi.encodePacked(msg.sender, _ops, _id));
        require(infoStaking[_value].isActive == false, "UserStake: Duplicate id");
        OptionsStaking memory options = infoOptions[_ops];
        uint256 _curPool = options.curPool + 1;
        uint256 maxPool = options.maxPool;
        require(_curPool <= maxPool, "UserStake: Max Amount");
        require(options.startTime <= block.timestamp, "UserStake: This Event Not Yet Start Time");
        require(block.timestamp <= options.endTime, "UserStake: This Event Over Time");

        ERC721(_erc721).transferFrom(msg.sender, address(this), _tokenId);
        countStakeNFT[_erc721]+=1;

        uint256 _lockDay =  options.lockDays;
        uint256 _endTime = block.timestamp + _lockDay;
        uint256 _reward;
        uint256 _level;

        if (infoVipUser[msg.sender].isVip == false) {
            _reward = options.rewardAmount;
            _level = 0;
        }
        else{
            uint256 _levelVip = infoVipUser[msg.sender].vipMember;
            vipInfo memory vips = infoVipList[_levelVip];
            uint256 _bonus = vips.bonusVip;
            _reward = options.rewardAmount + ((_bonus * (10**18) * options.rewardAmount)/ (100 * (10**18)));
            _level = _levelVip;
        }

        userInfoStaking memory info =
                userInfoStaking(
                    true, 
                    _level,
                    _tokenId, 
                    block.timestamp,
                    _endTime, 
                    _ops,
                    _lockDay,
                    _reward
                );
            infoStaking[_value] = info;
        infoOptions[_ops].curPool = _curPool;
        totalStaked = totalStaked + 1;
        totalAccumulatedRewardsReleased = totalAccumulatedRewardsReleased + _reward;

        emit UsersStaking(msg.sender, _tokenId, _ops, _id, _erc721);

        userInfoTotal storage infoTotals  = infoTotal[msg.sender];
        infoTotals.totalUserStaked = infoTotals.totalUserStaked + 1;
        infoTotals.totalUserReward = infoTotals.totalUserReward + _reward;
    }

    function userUnstake(uint256 _ops, uint256 _id, address _erc721) public nonReentrant {
        require(erc721Whitelist[_erc721] == true,"Contract is not in whitelist");
        bytes32 _value = keccak256(abi.encodePacked(msg.sender, _ops,_id));
        userInfoStaking storage info = infoStaking[_value];
        OptionsStaking storage options = infoOptions[_ops];
        require(info.isActive == true, "UnStaking: Not allowed unstake two times");

        uint256 claimableTokenId = _calcClaimableNFT(_value);
        require(claimableTokenId > 0, "Unstaking: Nothing to claim");

        ERC721(_erc721).transferFrom(address(this), msg.sender, claimableTokenId);

        emit UserUnstaking(msg.sender, claimableTokenId, _ops, _id, _erc721);

        info.endTime = block.timestamp;
        info.isActive = false;
        options.curPool = options.curPool - 1;
    }

    function _calcClaimableNFT(bytes32 _value)
        internal
        view 
        returns(uint256 claimableTokenId)
    {
        userInfoStaking memory info = infoStaking[_value];
        if(!info.isActive) return 0;
        if(block.timestamp < info.endTime) return 0;
        claimableTokenId = info.tokenId;
    }

    function claimReward(uint256 _ops, uint256 _id) public nonReentrant {
        bytes32 _value = keccak256(abi.encodePacked(msg.sender, _ops,_id));
        uint256 _claimableReward = _calcReward(_value,_ops);
        require(_claimableReward > 0, "Reward: Nothing to claim");
        tokenRR.transfer(msg.sender,_claimableReward);

        totalClaimedReward = totalClaimedReward + _claimableReward;
        userInfoStaking storage info = infoStaking[_value];
        info.reward = 0;
        emit UserReward(msg.sender, _claimableReward, _ops, _id);
        userInfoTotal storage infoTotals  = infoTotal[msg.sender];
        infoTotals.totalUserRewardClaimed = infoTotals.totalUserRewardClaimed + _claimableReward;
    }

    function _calcReward(bytes32 _value, uint256 _ops)
        internal
        view
        returns(uint256 claimableReward)
    {
        userInfoStaking memory info = infoStaking[_value];
        OptionsStaking storage options = infoOptions[_ops];
        uint256 releaseTime = info.endTime + options.durationLockReward;
        if(block.timestamp < releaseTime) return 0;
        claimableReward = info.reward;
    }

    function getInfoUserTotal(address account)
        public 
        view 
        returns (uint256,uint256) 
    {
        userInfoTotal memory info = infoTotal[account];
        return (info.totalUserStaked,info.totalUserReward);
    }

    function getInfoUserStaking(
        address account,
        uint256 _ops,
        uint256 _id
    )
        public
        view 
        returns (bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        bytes32 _value = keccak256(abi.encodePacked(account, _ops,_id));
        userInfoStaking memory info = infoStaking[_value];       
        return (
            info.isActive,
            info.vipMember,
            info.tokenId, 
            info.startTime,
            info.endTime,
            info.stakeOptions,
            info.fullLockedDays,
            info.reward
        );
    }

    function getBalanceToken(IERC20 _token) public view returns( uint256 ) {
        return _token.balanceOf(address(this));
    }
    
    // amount BNB
    function withdrawNative(uint256 _amount) public onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require( address(this).balance >= _amount ,"balanceOfNative:  is not enough");
        payable(msg.sender).transfer(_amount);
    }
    
    function withdrawToken(IERC20 _token, uint256 _amount) public onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require(_token.balanceOf(address(this)) >= _amount , "balanceOfToken:  is not enough");
        _token.transfer(msg.sender, _amount);
    }
    
    // all BNB
    function withdrawNativeAll() public onlyOwner {
        require(address(this).balance > 0 ,"balanceOfNative:  is equal 0");
        payable(msg.sender).transfer(address(this).balance);
    }
  
    function withdrawTokenAll(IERC20 _token) public onlyOwner {
        require(_token.balanceOf(address(this)) > 0 , "balanceOfToken:  is equal 0");
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    event Received(address, uint);
    receive () external payable {
        emit Received(msg.sender, msg.value);
    } 

}
