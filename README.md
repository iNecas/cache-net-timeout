# README


Seems like there is a bug in Ruby implementation, when combining timeout.rb with tempfile

Sample rails application to reproduce a strange behaviour with Net::HTTP in
combination with Tmpfile (used in Rails file store cache), leading to:

```
ERROR -- : Net::OpenTimeout:execution expired
ERROR -- : /home/inecas/.rbenv/versions/2.5.1/lib/ruby/2.5.0/timeout.rb:104:in `timeout'
/home/inecas/.rbenv/versions/2.5.1/lib/ruby/2.5.0/net/http.rb:935:in `connect'
/home/inecas/.rbenv/versions/2.5.1/lib/ruby/2.5.0/net/http.rb:920:in `do_start'
/home/inecas/.rbenv/versions/2.5.1/lib/ruby/2.5.0/net/http.rb:909:in `start'
/home/inecas/.rbenv/versions/2.5.1/lib/ruby/2.5.0/net/http.rb:609:in `start'
/home/inecas/.rbenv/versions/2.5.1/lib/ruby/2.5.0/net/http.rb:485:in `get_response'
```

It has been reproduced on ruby 2.5.1 from rbenv, as well as Satellite 6.5
SCL.

## Usage:

To see the failure, run

```
./fails.sh
```

Compare it to the version that works:

```
./works.sh
```

### Running in SCL

When reproducing on Satellite 6.5 instance, you need to run the scripts in tfm scl + remove the Gemfile.lock:

```
scl enable tfm bash
rm Gemfile.lock
./fails.sh
```

## Analysis

strace output has bee captured with `strace -f bash ./fails.sh 2> >(tee -a strace-fail.log)` and log
file is available in this repository.

The interesting part of the `strace-fail.log` starts at line 160081:

```strace
[pid 20834] unlink("/home/inecas/tmp/cache-net-timeout/tmp/cache/.hello20190309-20191-i43a3h" <unfinished ...>
[pid 20191] futex(0x55d4cd95e9f0, FUTEX_WAKE_PRIVATE, 1 <unfinished ...>
[pid 20834] <... unlink resumed> )      = -1 ENOENT (No such file or directory)
[pid 20191] <... futex resumed> )       = 0
[pid 20834] getpid( <unfinished ...>
[pid 20191] fstat(8,  <unfinished ...>
[pid 20834] <... getpid resumed> )      = 20191
[pid 20191] <... fstat resumed> {st_mode=S_IFSOCK|0777, st_size=0, ...}) = 0
[pid 20834] getpid()                    = 20191
[pid 20191] getpid( <unfinished ...>
[pid 20834] write(6, "!", 1 <unfinished ...>
[pid 20191] <... getpid resumed> )      = 20191
[pid 20834] <... write resumed> )       = 1
[pid 20191] getpid( <unfinished ...>
[pid 20834] futex(0x55d4cd95ea4c, FUTEX_WAIT_PRIVATE, 0, NULL <unfinished ...>
[pid 20191] <... getpid resumed> )      = 20191
[pid 20191] write(4, "!", 1 <unfinished ...>
[pid 20250] <... poll resumed> )        = 1 ([{fd=3, revents=POLLIN}])
[pid 20191] <... write resumed> )       = 1
[pid 20250] read(3,  <unfinished ...>
[pid 20191] getpid( <unfinished ...>
[pid 20250] <... read resumed> "!", 1024) = 1
[pid 20191] <... getpid resumed> )      = 20191
[pid 20250] read(3,  <unfinished ...>
[pid 20191] tgkill(20191, 20834, SIGVTALRM <unfinished ...>
```

It shows that the OS is switching between two processes, one trying to delete file (20834) while the other (20191) is setting up sleep.

The sleeps comes from [timeout.rb](https://github.com/ruby/ruby/blob/v2_5_1/lib/timeout.rb#L86), that is covering
the `OpenTimeout` of `Net::HTTP`. The unlink is originated in [tmpfile.rb](https://github.com/ruby/ruby/blob/v2_5_1/lib/tempfile.rb#L257).

When I modified the `timeout.rb` to give me more details, it turned out that it has not been sleeping for 60 seconds,
but the sleep returned immediately:

```ruby
y = Thread.start {
  Thread.current.name = from
  begin
    ret = sleep sec
    puts "===== sleep thread for #{sec} seconds, slept #{ret} instead"
  rescue => e
    x.raise e
  else
    x.raise exception, message
  end
}
return yield(sec)

# Produced
# ===== sleep thread for 60 seconds, slept 0 instead
```

This caused the Net::OpenTimeout to be raised. Once the timeouts are actually hitting, the whole new set
of possibilities for additional bugs can occur, such as [process hanging while cleaning the Tempfile](http://manageiq.org/blog/2017/09/finalizers-can-be-interrupted-from-time-to-time/), as our friends from ManageIQ have observed some time ago.

The important fact probably also is, that the tempfile code is run as part of [ObjectSpace finalizer](https://github.com/ruby/ruby/blob/v2_5_1/lib/tempfile.rb#L136):

```ruby
begin
  File.unlink(@tmpfile.path)
rescue Errno::ENOENT
end
```

So it looks like in the worse case scenario, the tempfile and timeout threads can influence each other in very unfortunate way, leading to very strange behavior.

## Mitigation

Making sure the tmpfiles are not used frequently (chaning from `Rails.cache.write` to `Rails.cache.fetch`)
made the issue go away. However, in case your code is using tmpfiles in combination with timeouts (might
be hidden, like here with `Rails.cache` and `Net::HTTP`), you might be hitting this issue in other scenarios.
