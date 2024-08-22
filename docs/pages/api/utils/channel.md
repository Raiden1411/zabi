## Channel
Channel used to manages the messages between threads.\
Main use case is for the websocket client.

## Init
Inits the channel.

## Deinit
Frees the channel.\
If the list still has items with allocated
memory this will not free them.

## Put
Puts an item in the channel.\
Blocks thread until it can add the item.

## TryPut
Tries to put in the channel. Will error if it can't.

## Get
Gets item from the channel. Blocks thread until it can get it.

## GetOrNull
Tries to get item from the channel.\
Returns null if there are no items.

