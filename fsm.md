Document to help keep track of the various FSM state transitions.

Dev id:
* WHO,r reads DEV_ID (0x74) -> state = DEVID,r
* DEVID,r reads I2C_ADDR -> state = DEVID,w
* DEVID,w reads DEV_ID -> write buffer and state = DATA,w
* (!DEVID),w writes like normal

i2c read/write:
* WHO,r reads I2C_ADDR ->
  - if RW=r: state = DATA,w (all reads dump the buffer)
  - if RW=w: state = CMD,r
* CMD,r reads cmd ->
  - if load command: do command
  - if action command: state = EXEC,r
* EXEC,r reads 1 byte ->
  - (this is to ensure naive scanners don't fuck with the state by trying
    to read action registers)
  - do command