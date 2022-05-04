// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VipOptions is Ownable {

    struct vipInfo{
        uint256 price;
        uint256 bonusVip;
        uint256 startTime;
        uint256 endTime;
        uint256 countedAmount
    }

    uint256 private countIdVips = 4;

    mapping(uint256 => vipInfo) public infoVipList;

    constructor() {
        infoVipList[1] = vipInfo(uint256(10000000000000000000000),uint256(20),uint256(1649934077),uint256(1682843442),0);
        infoVipList[2] = vipInfo(uint256(20000000000000000000000),uint256(50),uint256(1649934077),uint256(1682843442),0);
        infoVipList[3] = vipInfo(uint256(50000000000000000000000),uint256(80),uint256(1649934077),uint256(1682843442),0);
    }

    function setVips(
        uint256[] memory _optionInfoPrice,
        uint256[] memory _optionInfoBonusVip,
        uint256[] memory _optionInfoStartTime, 
        uint256[] memory _optionInfoEndTime
    ) public onlyOwner{
        require(_optionInfoPrice.length == _optionInfoPrice.length, "SetOptions: The inputs have the same length");
        require(_optionInfoPrice.length == _optionInfoStartTime.length, "SetOptions: The inputs have the same length");
        require(_optionInfoPrice.length == _optionInfoEndTime.length, "SetOptions: The inputs have the same length");
        for(uint256 i=0; i < _optionInfoPrice.length; i++){
            vipInfo memory info = vipInfo(
                _optionInfoPrice[i], 
                _optionInfoBonusVip[i], 
                _optionInfoStartTime[i],
                _optionInfoEndTime[i],
                0
            );
            infoVipList[countIdVips] = info;
            countIdVips+=1;
        }
    }

    function editVips(uint256 _opVips, uint256 _startTime, uint256 _endTime) public onlyOwner{
        require(_opVips < countIdVips, "EditOptions: The id is not valid");
        require(_startTime > 0, "EditOptions: The startTime is not valid");
        require(_endTime > 0, "EditOptions: The endTime is not valid");
        require(_startTime < _endTime, "EditOptions: The startTime is not valid");
        infoVipList[_opVips].startTime = _startTime;
        infoVipList[_opVips].endTime = _endTime;
    }
}
