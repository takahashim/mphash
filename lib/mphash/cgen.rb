# mphash.rb - minimal perfect hash library
#
# Copyright (C) 2008 Tanaka Akira  <akr@fsij.org>
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. The name of the author may not be used to endorse or promote products
#     derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

require 'erb'
require 'enumerator'

class MPHash
  def MPHash.gen_c_code(keys)
    h = MPHash::MPHF.new(keys)
    range = h.instance_variable_get(:@range)
    hashtuple = h.instance_variable_get(:@hashtuple)
    salts = hashtuple.instance_variable_get(:@salt)
    g = h.instance_variable_get(:@g)
    packed_g = []
    g.each_slice(16) {|vs|
      vs << 0 while vs.length < 16
      vs.reverse!
      packed_g << vs.inject(0) {|r, v| r * 4 + v }
    }
    formatted_g = packed_g.map {|v| "0x%x," % v }
    formatted_g.last.sub!(/,/, '')
    ranking = h.instance_variable_get(:@ranking)
    formatted_ranking = ranking.map {|v| "0x%x," % v }
    formatted_ranking << "0" if formatted_ranking.empty?
    formatted_ranking.last.sub!(/,/, '')
    ranking_small = h.instance_variable_get(:@ranking_small)
    formatted_ranking_small = ranking_small.map {|v| "0x%x," % v }
    formatted_ranking_small << "0" if formatted_ranking_small.empty?
    formatted_ranking_small.last.sub!(/,/, '')

    ERB.new(TEMPLATE_C, nil, '%').result(binding)
  end

  TEMPLATE_C = <<'End'
/* This file is generated by mphash. */
/* public domain */

<%= MPHash::JENKINS_LOOKUP3 %>

static struct {
  uint32_t range;
  uint32_t salt0, salt1, salt2;
  uint32_t g[<%= (g.length + 15) / 16 %>];
  uint32_t ranking[<%= formatted_ranking.length %>];
  unsigned char ranking_small[<%= formatted_ranking_small.length %>];
} mphf_parameter = {
  <%= range %>,
  <%= salts[0] %>, <%= salts[1] %>, <%= salts[2] %>,
  {
% formatted_g.each_slice(6) {|vs|
    <%= vs.join('') %>
% }
  },
  {
% formatted_ranking.each_slice(6) {|vs|
    <%= vs.join('') %>
% }
  },
  {
% formatted_ranking_small.each_slice(15) {|vs|
    <%= vs.join('') %>
% }
  }
};

#define RANK_BLOCKSIZE <%= MPHash::MPHF::RANK_BLOCKSIZE %>
#define RANK_SMALLBLOCKSIZE <%= MPHash::MPHF::RANK_SMALLBLOCKSIZE %>

#define GCC_VERSION_BEFORE(major, minor, patchlevel) \
  (defined(__GNUC__) && !defined(__INTEL_COMPILER) && \
   ((__GNUC__ < (major)) ||  \
    (__GNUC__ == (major) && __GNUC_MINOR__ < (minor)) || \
    (__GNUC__ == (major) && __GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ < (patchlevel))))

#if defined(__GNUC__) && !GCC_VERSION_BEFORE(3,4,0)
# define popcount(w) __builtin_popcountl(w)
#else
# error "popcount not implemented"
#endif

#define GPOPCOUNT(w) popcount(((w) & 0x55555555) & ((w) >> 1))

static unsigned long mphf(const void *key, size_t length)
{
  uint32_t fullhash0, fullhash1, fullhash2;
  uint32_t h[3];
  uint32_t ph, mph, a, b, c, u;
  int i;
  fullhash0 = mphf_parameter.salt0;
  fullhash1 = mphf_parameter.salt1;
  hashlittle2(key, length, &fullhash0, &fullhash1);
  fullhash2 = hashlittle(key, length, mphf_parameter.salt2);
  h[0] = fullhash0 % mphf_parameter.range;
  h[1] = (fullhash1 % mphf_parameter.range) + mphf_parameter.range;
  h[2] = (fullhash2 % mphf_parameter.range) + mphf_parameter.range*2;
  i = ((mphf_parameter.g[h[0] / 16] >> (2 * (h[0] % 16))) & 0x3) +
      ((mphf_parameter.g[h[1] / 16] >> (2 * (h[1] % 16))) & 0x3) +
      ((mphf_parameter.g[h[2] / 16] >> (2 * (h[2] % 16))) & 0x3);
  ph = h[i % 3];
  a = ph / RANK_BLOCKSIZE;
  b = ph % RANK_BLOCKSIZE;
  c = b % RANK_SMALLBLOCKSIZE;
  b = b / RANK_SMALLBLOCKSIZE;
  mph = 0;
  if (a != 0)
    mph = mphf_parameter.ranking[a-1];
  if (b != 0)
    mph += mphf_parameter.ranking_small[a*(RANK_BLOCKSIZE/RANK_SMALLBLOCKSIZE-1)+b-1];
  if (c != 0) {
    u = mphf_parameter.g[ph / 16] & ((1 << (c*2)) - 1);
    mph += c - GPOPCOUNT(u);
  }
  return mph;
}

#if 0
int main(int argc, char **argv)
{
  uint32_t h1;
% keys.each {|k| 
  //h1 = phf(<%=k.dump%>, <%=k.length%>); if (h1 != <%=h.phf(k).to_s%>) printf("bug:phf: %s : expected:%u but:%u\n", <%=k.dump%>, <%=h.mphf(k).to_s%>, h1);
  h1 = mphf(<%=k.dump%>, <%=k.length%>); if (h1 != <%=h.mphf(k).to_s%>) printf("bug:mphf: %s : expected:%u but:%u\n", <%=k.dump%>, <%=h.mphf(k).to_s%>, h1);
% }
  return 0;
}
#endif
End
end

