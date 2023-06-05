pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract REXProtocolToken is ERC20 {
    ERC20 public constant RICOCHET_TOKEN =
        ERC20(0x263026E7e53DBFDce5ae55Ade22493f828922965);
    address private constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    event SupportREX(address indexed user, uint amount);

    constructor() ERC20("REX Protocol Token", "REX") {}

    function supportREX(uint amount) external {
        require(totalSupply() < 10000000 * 10 ** decimals(), "max supply");
        require(msg.sender != DEAD_ADDRESS, "invalid address");
        require(
            RICOCHET_TOKEN.transferFrom(msg.sender, DEAD_ADDRESS, amount),
            "transferFrom failed"
        );
        _mint(msg.sender, amount);
        emit SupportREX(msg.sender, amount);
    }
}
