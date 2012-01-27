# 人人网 FS

依照 UNIX 一切皆文件的哲学思想，基于 FUSE (Filesystem in Userspace)，将人人网的数据映射为一个文件系统。

这个程序还很粗糙，其实也只是我一时心血来潮写的一个小程序，如果你有兴趣的话也可以一起来改进它~

## 使用方式

首先你需要到人人网的开放平台上申请一个新的桌面应用，因为这个应用没有提交申请，所以其他人是用不了里面写的 API Key 和 Secret Key 的。

然后需要安装 FUSE，Mac OS X 下安装的是 [OSXFUSE](http://osxfuse.github.com/)。

除了 FUSE 之外，还需要安装 [SBJson](https://github.com/upsuper/json-framework) 这个 JSON 解析库。点击前面的地址，然后 `git clone` 后用 Xcode 打开编译，并将编译后的 SBJson.framework 文件夹拷贝到 /Library/Frameworks 下面。
事实上这个库的官方源在 https://github.com/stig/json-framework，我对它进行了一些修改，并且在这个项目中依赖这些修改。我已经申请合并到其代码中去，估计一段时间后就可以通过了吧。

最后打开 RenrenFS 的工程，将之前申请的 API Key 和 Secret Key 填入RenrenFS.m 的对应位置，然后编译执行。

执行后会显示人人登入窗口，登入并授权以后，会自动挂载文件系统，并在 Finder 里显示出来。

## 设想但尚未实现的功能

* **日志访问**

    最初设想中主要就是日志和相册的访问可以通过文件的形式进行。日志显示为一个 HTML 文件，可以直接从文件系统中打开浏览。
    
    但是实现的过程中，由于人人网对 API 访问频率的限制，日志暂时还没有好的实现方法。

* **新建相册、上传照片**

    最初设想中允许用户在自己的照片文件夹中新建文件夹，并将此操作映射到新建相册的操作。还设想通过拖动照片文件到相册内，直接实现上传照片。

    这个部分只是纯粹因为懒所以还没实现而已……

* **发布日志**

    与上传照片相似，设想中还有通过这个发布日志。将写好的日志文件，无论是 HTML 的还是 DOC 或者 TXT 格式的，复制到自己的日子文件夹里就可以实现发布日志的操作。

* **显示用户头像、相册封面**

    对于用户文件夹，将用户头像显示为其图标，而对于相册文件夹将相册封面显示为其图标。

    这需要 Mac OS X 的 Resource Fork 这一功能，由于还没有研究清楚实现方法，所以没有实现。

## 已知局限性

* **可能显示不完全**

    出于偷懒的考虑，对于所有需要分页获取的信息全部没有设计多次获取，仅仅是将每页数量放在一个较大的数值上以尽量抓取多的数据。比如只会显示1000个相册，每个相册只会显示200张相片等。

* **不能刷新内容**

    出于效率和 API 访问频率限制的考虑，所有的数据都会被缓存，并且没有自动刷新的机制，也就是说一旦一个数据被抓取下来，除非卸载这个文件系统，否则数据不可能被更新。

    其中照片数据还被永久缓存于磁盘上，如果不手工清除，则永远不会更新。

* **代码混乱、缺乏注释和文档**
    
    因为没有太多地对整体构架进行思考，所以现在的代码十分混乱。这一点我在考虑很快改进。

    至于注释和文档……程序员最讨厌的两件事情之一相信你们都懂的。

## 主要限制

* **人人网 API 访问频率限制**

    人人网的 API 对于普通应用限制访问频率为每小时150次查询。这对于实现文件系统映射的很多功能都是不够的。即使缓存信息，对于部分项目比如日志的访问等，仍然可能产生突发大访问量。
