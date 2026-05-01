import std/[asyncdispatch, deques]

type
  MailboxClosedError* = object of CatchableError

  Mailbox*[T] = ref object
    queue: Deque[T]
    waiters: Deque[Future[T]]
    closed: bool

# ------------------------------------------------------------------------------
#
# newMailbox:
#
# ------------------------------------------------------------------------------

proc newMailbox*[T](): Mailbox[T] =
  result = Mailbox[T]()
  result.queue = initDeque[T]()
  result.waiters = initDeque[Future[T]]()
  result.closed = false

# ------------------------------------------------------------------------------
#
# isClosed:
#
# ------------------------------------------------------------------------------

proc isClosed*[T](m: Mailbox[T]): bool =
  if m.isNil:
    return true

  result = m.closed

# ------------------------------------------------------------------------------
#
# len:
#
# ------------------------------------------------------------------------------

proc len*[T](m: Mailbox[T]): int =
  if m.isNil:
    return 0

  result = m.queue.len

# ------------------------------------------------------------------------------
#
# pendingReceivers:
#
# ------------------------------------------------------------------------------

proc pendingReceivers*[T](m: Mailbox[T]): int =
  if m.isNil:
    return 0

  result = m.waiters.len

# ------------------------------------------------------------------------------
#
# close:
#
# ------------------------------------------------------------------------------

proc close*[T](m: Mailbox[T]) =
  if m.isNil or m.closed:
    return

  m.closed = true

  while m.waiters.len > 0:
    let fut = m.waiters.popFirst()

    if not fut.finished:
      fut.fail(newException(MailboxClosedError, "mailbox is closed"))

# ------------------------------------------------------------------------------
#
# send:
#
# ------------------------------------------------------------------------------

proc send*[T](m: Mailbox[T]; value: sink T) =
  ## Send one value.
  ##
  ## If a receiver is already waiting, its Future is completed immediately.
  ## Otherwise the value is queued.
  ##
  ## This mailbox is intended for async tasks on the same asyncdispatch event
  ## loop.  It is not a thread-safe queue.
  if m.isNil:
    raise newException(MailboxClosedError, "mailbox is nil")

  if m.closed:
    raise newException(MailboxClosedError, "mailbox is closed")

  while m.waiters.len > 0:
    let fut = m.waiters.popFirst()

    if fut.finished:
      continue

    fut.complete(value)
    return

  m.queue.addLast(value)

# ------------------------------------------------------------------------------
#
# tryRecv:
#
# ------------------------------------------------------------------------------

proc tryRecv*[T](m: Mailbox[T]; value: var T): bool =
  if m.isNil or m.queue.len == 0:
    return false

  value = m.queue.popFirst()
  result = true

# ------------------------------------------------------------------------------
#
# recv:
#
# ------------------------------------------------------------------------------

proc recv*[T](m: Mailbox[T]): Future[T] =
  ## Receive one value.
  ##
  ## If a value is already queued, the returned Future is already completed.
  ## Otherwise the Future is completed by a later send().
  if m.isNil:
    result = newFuture[T]("Mailbox.recv")
    result.fail(newException(MailboxClosedError, "mailbox is nil"))
    return

  result = newFuture[T]("Mailbox.recv")

  if m.queue.len > 0:
    result.complete(m.queue.popFirst())
    return

  if m.closed:
    result.fail(newException(MailboxClosedError, "mailbox is closed"))
    return

  m.waiters.addLast(result)

# ------------------------------------------------------------------------------
#
# drain:
#
# ------------------------------------------------------------------------------

proc drain*[T](m: Mailbox[T]): seq[T] =
  ## Drain all currently queued values.
  ##
  ## This does not wait for future values.
  if m.isNil:
    return @[]

  result = newSeqOfCap[T](m.queue.len)

  while m.queue.len > 0:
    result.add(m.queue.popFirst())

# ------------------------------------------------------------------------------
#
# clear:
#
# ------------------------------------------------------------------------------

proc clear*[T](m: Mailbox[T]) =
  ## Drop queued values.
  ##
  ## Waiting receivers are not cancelled.  Use close() to fail waiters.
  if m.isNil:
    return

  m.queue.clear()
