#!/usr/bin/env python
# - * - coding: UTF-8 - * -

import os
import json

from os import path
from sys import argv, stderr
from stat import S_IFDIR, S_IFREG
from time import time, mktime, strptime
from errno import ENOENT, EACCES, ENOSYS, EEXIST
from urllib import urlencode, urlretrieve
from hashlib import md5
from getpass import getpass
from httplib2 import Http
from threading import Lock

from fuse import FUSE, FuseOSError, Operations, LoggingMixIn

from config import *

RENREN_API_URI = 'http://api.renren.com/restserver.do'

def convert_time(t):
    return mktime(strptime(t, '%Y-%m-%d %H:%M:%S'))

def makedirs(path):
    try:
        os.makedirs(path)
    except OSError, e:
        if e.errno == EEXIST:
            pass
        else:
            raise

def encode_strings(s):
    if type(s) == unicode:
        s = s.encode('utf8')
    s = s.replace('\\', '\\\\')
    s = s.replace('"', '\\"')
    return s

class RenrenFS(LoggingMixIn, Operations):
    """Renren filesystem"""

    def __init__(self, access_token, cache_path):
        self._access_token = access_token
        #self._user_cache = LRUCache(USER_CACHE_SIZE)
        self._user_cache = {}
        self._conn = Http()
        self._uid = self._request_api('users.getLoggedInUser')['uid']
        self._photo_cache = path.join(cache_path, 'photos')
        self._rwlock = Lock()
        self._cache_lock = Lock()

    def _request_api(self, method, **args):
        '''请求人人 API'''
        print >>stderr, 'request:', method, args
        data = {}
        data.update(args)
        data.update({
            'method': method,
            'v': '1.0',
            'access_token': self._access_token,
            'format': 'JSON'
            })
        # 计算签名
        sig = ['%s=%s' % (k, v) for k, v in data.iteritems()]
        sig.sort()
        sig = ''.join(sig) + SECRET_KEY
        sig = md5(sig).hexdigest()
        data['sig'] = sig
        # 发送请求
        body = urlencode(data)
        headers = {'Content-Type': 'application/x-www-form-urlencoded'}
        resp, content = \
            self._conn.request(RENREN_API_URI, 'POST', body, headers)
        if resp.status == 200:
            content = json.loads(content)
            if 'error_code' in content:
                error_msg = 'Error#%s %s' % \
                        (content['error_code'], content['error_msg'])
                raise Warning(error_msg.encode('utf8'))
            return content
        else:
            raise Exception()

    def _parse_path(self, path):
        path = path.split('/')[1:]
        info = ('user', self._uid)
        for s in path:
            if not s:
                continue
            localized = False
            if len(s) > 10 and s[-10:] == '.localized':
                s = s[:-10]
                localized = True
            ftype = info[0]
            if ftype == 'user':
                uid = info[1]
                if s == 'Friends':
                    if uid != self._uid:
                        info = None
                        break
                    info = ('friends', uid)
                elif s == 'Photos':
                    info = ('photos', uid)
                # elif s == 'Blog':
                #     info = ('blog', uid)
                elif s == '.localized' and info[-1] == 'localized':
                    info = ('localize', ) + info[:-1]
                else:
                    info = None
                    break
            elif ftype == 'friends':
                assert info[1] == self._uid
                if s[:5] != 'user_' or not s[5:].isdigit():
                    info = None
                    break
                new_uid = int(s[5:])
                uid = info[1]
                if new_uid in self._get_user_info(uid, 'friends'):
                    info = ('user', new_uid)
                else:
                    info = None
                    break
            elif ftype == 'photos':
                if s[:6] != 'album_' or not s[6:].isdigit():
                    info = None
                    break
                aid = int(s[6:])
                uid = info[1]
                if aid in self._get_user_info(uid, 'albums'):
                    info = ('album', uid, aid)
                else:
                    info = None
                    break
            elif ftype == 'album':
                if s == '.localized' and info[-1] == 'localized':
                    info = ('localize', ) + info[:-1]
                elif s[:6] != 'photo_' or s[-4:] != '.jpg' or \
                        not s[6:-4].isdigit():
                    info = None
                    break
                else:
                    pid = int(s[6:-4])
                    uid = info[1]
                    aid = info[2]
                    if pid in self._get_photos(uid, aid):
                        info = ('photo', uid, aid, pid)
                    else:
                        info = None
                        break
            elif ftype == 'localize':
                if s[-8:] == '.strings':
                    info = ('strings', ) + info[1:]
                else:
                    info = None
                    break
            else:
                info = None
                break
            if localized:
                info += ('localized', )
        if not info:
            raise FuseOSError(ENOENT)
        return info

    def _get_user_info(self, uid, field='base'):
        if uid not in self._user_cache:
            self._user_cache[uid] = {}
        user = self._user_cache[uid]
        if field in user:
            return user[field]
        self._cache_lock.acquire()
        if field == 'base':
            user_info = self._request_api('users.getProfileInfo',
                    uid=uid, fields='base_info')
            user['base'] = {
                    'name': user_info['name'],
                    'head': user_info['headurl'],
                    'sex': user_info['base_info']['gender'],
                    }
        elif field == 'counts':
            counts = self._request_api('users.getProfileInfo', uid=uid,
                    fields='blogs_count,albums_count,friends_count')
            user['counts'] = {
                    'blogs': counts['blogs_count'],
                    'albums': counts['albums_count'],
                    'friends': counts['friends_count'],
                    }
        elif field == 'friends':
            assert uid == self._uid
            orig = self._request_api('friends.getFriends', count=2000)
            friends = []
            user['friends'] = friends
            for friend in orig:
                friend_id = friend['id']
                friends.append(friend_id)
                if friend_id not in self._user_cache:
                    self._user_cache[friend_id] = {}
                u = self._user_cache[friend_id]
                if 'base' not in u:
                    u['base'] = {
                            'name': friend['name'],
                            'head': friend['headurl'],
                            'sex': friend['sex']
                            }
        elif field == 'albums':
            orig = self._request_api('photos.getAlbums', uid=uid, count=1000)
            albums = {}
            for album in orig:
                albums[album['aid']] = album
                del album['aid'], album['uid']
            user['albums'] = albums
        self._cache_lock.release()
        return user[field]
    
    def _get_photos(self, uid, aid):
        album = self._get_user_info(uid, 'albums')[aid]
        if 'photos' in album:
            return album['photos']
        self._cache_lock.acquire()
        orig = self._request_api('photos.get', uid=uid, aid=aid, count=200)
        photos = {}
        for photo in orig:
            photos[photo['pid']] = photo
            del photo['pid'], photo['aid'], photo['uid']
        album['photos'] = photos
        self._cache_lock.release()
        return photos

    def _get_photo(self, uid, aid, pid):
        dirname = path.join(self._photo_cache, str(uid), str(aid))
        filename = path.join(dirname, str(pid) + '.jpg')
        if not path.exists(filename):
            if not path.isdir(dirname):
                makedirs(dirname)
            photo = self._get_photos(uid, aid)[pid]
            urlretrieve(photo['url_large'], filename)
        return filename

    def getattr(self, path, fh=None):
        result = self._parse_path(path)
        ftype = result[0]
        uid = result[1]
        st = {}
        if ftype == 'user':
            st.update({
                'st_mode': S_IFDIR | 0755,
                'st_nlink': 5 if uid == self._uid else 4
                })
        elif ftype == 'friends':
            friends_count = self._get_user_info(uid, 'counts')['friends']
            st.update({
                'st_mode': S_IFDIR | 0555,
                'st_nlink': friends_count + 2
                })
        elif ftype == 'photos':
            albums_count = self._get_user_info(uid, 'counts')['albums']
            st.update({
                'st_mode': S_IFDIR | 0755,
                'st_nlink': albums_count + 2
                })
        elif ftype == 'album':
            aid = result[2]
            album = self._get_user_info(uid, 'albums')[aid]
            size = album['size']
            modes = {-1: 0700, 1: 0750, 3: 0750, 4: 0700, 99: 0755}
            mode = modes[album['visible']]
            st.update({
                'st_mode': S_IFDIR | mode,
                'st_nlink': 2,
                'st_ctime': convert_time(album['create_time']),
                'st_mtime': convert_time(album['update_time']),
                })
        elif ftype == 'photo':
            aid = result[2]
            pid = result[3]
            photo = self._get_photos(uid, aid)[pid]
            cache_file = self._get_photo(uid, aid, pid)
            os_stat = os.lstat(cache_file)
            st.update({
                'st_mode': S_IFREG | 0644,
                'st_size': os_stat.st_size,
                'st_mtime': convert_time(photo['time']),
                'st_ctime': convert_time(photo['time'])
                })
        # elif ftype == 'blog':
        #     st.update({
        #         'st_mode': S_IFDIR | 0755,
        #         'st_nlink': 2
        #         })
        elif ftype == 'localize':
            st.update({
                'st_mode': S_IFDIR | 0555,
                'st_nlink': 2
                })
        elif ftype == 'strings':
            st.update({
                'st_mode': S_IFREG | 0444,
                'st_size': len(self._read(path))
                })
        if 'st_ctime' not in st:
            st['st_ctime'] = time()
        if 'st_mtime' not in st:
            st['st_mtime'] = time()
        if 'st_atime' not in st:
            st['st_atime'] = time()
        return st

    def readdir(self, path, fh):
        result = self._parse_path(path)
        ret = ['.', '..']
        ftype = result[0]
        uid = result[1]
        if result[-1] == 'localized':
            ret += ['.localized']
        if ftype == 'user':
            if uid == self._uid:
                ret += ['Friends']
            # ret += ['Photos', 'Blog']
            ret += ['Photos']
        elif ftype == 'friends':
            ret += ['user_' + str(friend) + '.localized' for friend in
                    self._get_user_info(uid, 'friends')]
        elif ftype == 'photos':
            ret += ['album_' + str(album) + '.localized' for album in
                    self._get_user_info(uid, 'albums').iterkeys()]
        elif ftype == 'album':
            ret += ['photo_' + str(photo) + '.jpg' for photo in
                    self._get_photos(uid, result[2]).iterkeys()]
        elif ftype == 'localize':
            ret += ['zh_CN.strings']
        return ret

    def _get_filename(self, path):
        result = self._parse_path(path)
        ftype = result[0]
        uid = result[1]
        if ftype == 'photo':
            filename = self._get_photo(uid, result[2], result[3])
        elif ftype == 'strings':
            filename = None
        else:
            raise FuseOSError(ENOSYS)
        return filename

    def access(self, path, mode):
        try:
            filename = self._get_filename(path)
        except FuseOSError, e:
            if e.errno == ENOSYS:
                return super(RenrenFS, self).access(path, mode)
            else:
                raise
        if filename and not os.access(filename, mode):
            raise FuseOSError(EACCES)
    
    def open(self, path, flags):
        filename = self._get_filename(path)
        if filename:
            return os.open(filename, flags)
        else:
            return super(RenrenFS, self).open(path, flags)

    def _read(self, path):
        result = self._parse_path(path)
        ftype = result[0]
        if ftype == 'strings':
            result = result[1:]
            ftype = result[0]
            uid = result[1]
            if ftype == 'user':
                realname = self._get_user_info(uid)['name']
                return '"%s" = "%s";\n' % \
                        ('user_%d' % (uid, ), encode_strings(realname))
            elif ftype == 'album':
                aid = result[2]
                name = self._get_user_info(uid, 'albums')[aid]['name']
                return '"%s" = "%s";\n' % \
                        ('album_%d' % (aid, ), encode_strings(name))
        else:
            return ''

    def read(self, path, size, offset, fh):
        filename = self._get_filename(path)
        if filename:
            with self._rwlock:
                os.lseek(fh, offset, 0)
                return os.read(fh, size)
        else:
            return self._read(path)

    def release(self, path, fh):
        filename = self._get_filename(path)
        if filename:
            return os.close(fh)
        else:
            return super(RenrenFS, self).release(path, fh)

if __name__ == '__main__':
    if len(argv) != 2:
        print 'usage: %s <mountpoint>' % (argv[0], )
        exit(1)
    url = 'https://graph.renren.com/oauth/authorize?' + urlencode({
        'client_id': API_KEY,
        'redirect_uri': 'http://graph.renren.com/oauth/login_success.html',
        'response_type': 'token',
        'scope': 'read_user_blog read_user_album read_user_photo'
        })
    print url
    access_token = raw_input('Access Token: ')
    fuse = FUSE(RenrenFS(access_token, path.realpath(FILE_CACHE_DIR)),
            argv[1], foreground=True)
