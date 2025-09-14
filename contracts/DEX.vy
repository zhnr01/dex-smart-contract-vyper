# @version 0.4.3

from ethereum.ercs import IERC20

interface Exchange:
    def getReserve() -> uint256: view

    def getAmount(
        inputAmount: uint256,
        inputReserve: uint256,
        outputReserve: uint256
    ) -> uint256: view


tokenAddress: public(address)

@deploy
def __init__(_token: address):
    # Ensure the token address is not the zero address (0x000...)
    assert _token != empty(address), "invalid token address"
    self.tokenAddress = _token


@external
@payable
def addLiquidity(_tokenAmount: uint256):
    token: IERC20 = IERC20(self.tokenAddress)
    extcall token.transferFrom(msg.sender, self, _tokenAmount)

@external
@view
def getReserve() -> uint256:
    return staticcall IERC20(self.tokenAddress).balanceOf(self)


@external
@view
def getAmount(inputAmount: uint256,
              inputReserve: uint256,
              outputReserve: uint256) -> uint256:
    assert inputReserve > 0 and outputReserve > 0, "invalid reserves"
    return (inputAmount * outputReserve) // (inputReserve + inputAmount)

@external
@view
def getTokenAmount(_ethSold: uint256) -> uint256:
    assert _ethSold > 0, "ethSold is too small"

    tokenReserve: uint256 = staticcall Exchange(self).getReserve()

    return staticcall Exchange(self).getAmount(
        _ethSold,
        self.balance,
        tokenReserve
    )

@external
@view
def getEthAmount(_tokenSold: uint256) -> uint256:
    # Make sure the user is selling more than 0 tokens
    assert _tokenSold > 0, "tokenSold is too small"
    
    # Get how many tokens the DEX currently holds
    tokenReserve: uint256 = staticcall Exchange(self).getReserve()
    
    # Use AMM formula to calculate ETH output
    return staticcall Exchange(self).getAmount(
        _tokenSold,     # Input amount (tokens being sold)
        tokenReserve,   # Token reserve in pool
        self.balance    # ETH reserve in pool
    )

@external
@payable
def ethToTokenSwap(_minTokens: uint256):
    # Get the current token reserve in the pool
    tokenReserve: uint256 = staticcall Exchange(self).getReserve()

    # Calculate how many tokens the user will get for the ETH they sent (msg.value)
    # We subtract msg.value from self.balance to avoid counting the ETH they just sent
    tokensBought: uint256 = staticcall Exchange(self).getAmount(
        msg.value,                # ETH being sold
        self.balance - msg.value, # ETH reserve before this transaction
        tokenReserve              # Token reserve
    )

    # Ensure the trade meets the user's minimum acceptable amount (slippage protection)
    assert tokensBought >= _minTokens, "insufficient output amount"

    # Transfer the purchased tokens to the user
    extcall IERC20(self.tokenAddress).transfer(msg.sender, tokensBought)

@external
def tokenToEthSwap(_tokensSold: uint256, _minEth: uint256):
    # Get the current token reserve in the pool
    tokenReserve: uint256 = staticcall Exchange(self).getReserve()

    # Calculate how much ETH the user will get for selling their tokens
    ethBought: uint256 = staticcall Exchange(self).getAmount(
        _tokensSold,      # Tokens being sold
        tokenReserve,     # Token reserve
        self.balance      # ETH reserve
    )

    # Make sure the trade gives at least the user's minimum acceptable ETH (slippage protection)
    assert ethBought >= _minEth, "insufficient output amount"

    # Pull the tokens from the user's wallet into the DEX contract
    extcall IERC20(self.tokenAddress).transferFrom(
        msg.sender,   # From: the user
        self,         # To: the DEX contract
        _tokensSold   # Amount of tokens
    )

    # Send ETH from the DEX to the user
    send(msg.sender, ethBought)

