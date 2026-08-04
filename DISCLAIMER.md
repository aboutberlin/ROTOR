# Disclaimer and assumption of risk

**Read this before running the software. By using it you accept everything below.**

This is free software shared as-is by an individual, with no company, no support
contract, no warranty and no safety certification behind it.

## Hard requirement: the motor must be secured on a bench

**Do not run this software against a motor that is not rigidly mounted.**

Before connecting:

- **Bolt the motor to a test bench or fixture.** Not clamped, not held, not
  resting on a desk. Bolted.
- **Remove the load.** No wheel, no arm, no linkage, no gearbox output coupled
  to anything that can move.
- **Clear the rotation envelope** and keep hands, cables and tools out of it.
- **Have a physical power cut within reach** — a switch or connector you can
  operate without going through this software — and test that it works first.

This is not a recommendation. Parameter detection, encoder detection, mode
switching, direction changes and control commands all cause **sudden, powered
rotation with no warning**. An unsecured motor will move itself, and a coupled
load will move with it.

If the motor is not bolted down and unloaded, stop here.

## What this software actually does

It drives brushless motor controllers over a serial link. It can:

- energise a motor and make it **spin without warning**, including at speed
- command current, torque, duty cycle, position and velocity
- run parameter detection routines that **deliberately move the motor**
- change current, voltage, power and speed limits stored in the controller
- **erase and rewrite controller firmware**
- write configuration into non-volatile memory

A mistake in any of the above can destroy the motor, destroy the controller,
damage whatever the motor is attached to, start a fire, or injure someone
standing near it. Motors on a bench have thrown loads. Firmware writes have
bricked hardware. Wrong limits have burned windings.

## No warranty

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

There is no promise that it works, that it is correct, that it matches any
vendor's specification, that it will not damage your equipment, or that any
future version will keep working.

## No liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE AUTHORS
OR CONTRIBUTORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

This covers, without limitation: damaged or destroyed motors, controllers, power
supplies, test rigs, tooling, workpieces and surrounding property; lost work,
lost data, lost time and lost research results; and any injury arising from
equipment behaviour.

## By using this software you agree that

1. You use it **entirely at your own risk**.
2. You are solely responsible for the safety of your hardware, your workspace
   and every person near it.
3. You will not hold the authors or contributors responsible for any loss,
   damage or injury of any kind, however caused.
4. You have verified that every limit you send is safe for **your** motor,
   controller and power supply — not for the hardware the author happened to own.
5. You accept that a successful serial write does **not** mean the device
   accepted, applied or persisted the value.
6. You accept that firmware operations can render hardware unusable and may
   require external recovery equipment you do not have.

**If you do not accept this, do not use the software.**

## Basic safety practice

Not exhaustive, and not a substitute for your own judgement:

- Unload and mechanically secure the motor before energising it.
- Keep clear space around anything that can rotate. Assume it will.
- Keep a physical means of cutting power within reach, and test it first.
- Back up controller configuration before changing it, and read it back after.
- Do not run firmware operations on hardware you cannot afford to lose, and do
  not interrupt power during them.
- Treat every limit value as dangerous until you have confirmed it against your
  own hardware's ratings.

## Independence

This is an independent project. It is not affiliated with, endorsed by,
supported by, or certified by any hardware vendor. Nothing here carries any
vendor's approval, and no vendor is responsible for it.

---

*Note on enforceability: liability limits are read differently across
jurisdictions, and some — particularly for personal injury or gross negligence —
will not enforce a full waiver regardless of wording. This document states the
intent and the risk plainly; it is not legal advice and has not been reviewed by
a lawyer.*
