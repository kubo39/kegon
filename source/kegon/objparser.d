// ported from meshoptimizer's objparser.

/*
MIT License

Copyright (c) 2016-2018 Arseny Kapoulkine

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
module kegon.objparser;

import core.stdc.math : pow;
import core.stdc.stdio;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memchr, memcpy, memmove;

private:

void growArray(T)(ref T* data, ref size_t capacity)
{
	size_t newcapacity = capacity == 0 ? 32 : capacity + capacity / 2;
	T* newdata = cast(T*) malloc(newcapacity * (T*).sizeof);

	if (data)
	{
		memcpy(cast(void*) newdata, cast(void*) data, capacity * T.sizeof);
		free(data);
	}

	data = newdata;
	capacity = newcapacity;
}

int fixupIndex(int index, size_t size)
{
	return index >= 0 ? index - 1 : cast(int)size + index;
}

int parseInt(const(char)* s, const(char)** end)
{
	// skip whitespace
	while (*s == ' ' || *s == '\t')
		s++;

	// read sign bit
	int sign = (*s == '-');
	s += (*s == '-' || *s == '+') ? 1 : 0;

	uint result = 0;

	for (;;)
	{
		if (cast(uint)(*s - '0') < 10)
			result = result * 10 + (*s - '0');
		else
			break;
		s++;
	}

	// return end-of-string
	*end = s;

	return sign ? -cast(int) result : cast(int) result;
}

const(double)[] digits = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
const(double)[] powers = [
	1e0, 1e+1, 1e+2, 1e+3, 1e+4, 1e+5, 1e+6, 1e+7, 1e+8, 1e+9, 1e+10, 1e+11, 1e+12,
	1e+13, 1e+14, 1e+15, 1e+16, 1e+17, 1e+18, 1e+19, 1e+20, 1e+21, 1e+22
	];

float parseFloat(const(char)* s, const(char)** end)
{
	// skip whitespace
	while (*s == ' ' || *s == '\t')
		s++;

	// read sign
	double sign = (*s == '-') ? -1 : 1;
	s += (*s == '-' || *s == '+');

	// read integer part
	double result = 0;
	int power = 0;

	while (cast(uint)(*s - '0') < 10)
	{
		result = result * 10 + digits[*s - '0'];
		s++;
	}

	// read fractional part
	if (*s == '.')
	{
		s++;

		while (cast(uint)(*s - '0') < 10)
		{
			result = result * 10 + digits[*s - '0'];
			s++;
			power--;
		}
	}

	// read exponent part
	if ((*s | ' ') == 'e')
	{
		s++;

		// read exponent sign
		int expsign = (*s == '-') ? -1 : 1;
		s += (*s == '-' || *s == '+');

		// read exponent
		int exppower = 0;

		while (cast(uint)(*s - '0') < 10)
		{
			exppower = exppower * 10 + (*s - '0');
			s++;
		}

		// done!
		power += expsign * exppower;
	}

	// return end-of-string
	*end = s;

	// note: this is precise if result < 9e15
	// for longer inputs we lose a bit of precision here
	if (cast(uint)(-power) < powers.length)
		return cast(float)(sign * result / powers[-power]);
	else if (cast(uint)(power) < powers.length)
		return cast(float)(sign * result * powers[power]);
	else
		return cast(float)(sign * result * pow(10.0, power));
}

const(char)* parseFace(const(char)* s, ref int vi, ref int vti, ref int vni)
{
	while (*s == ' ' || *s == '\t')
		s++;

	vi = parseInt(s, &s);

	if (*s != '/')
		return s;
	s++;

	// handle vi//vni indices
	if (*s != '/')
		vti = parseInt(s, &s);

	if (*s != '/')
		return s;
	s++;

	vni = parseInt(s, &s);

	return s;
}

public:

struct ObjFile
{
	// positions; stride 3 (xyz)
	float* v;
	size_t v_size;
	size_t v_cap;

	// texture coordinates; stride 3 (uvw)
	float* vt;
	size_t vt_size;
	size_t vt_cap;

	// vertex normals; stride 3 (xyz)
	float* vn;
	size_t vn_size;
	size_t vn_cap;

	// face elements; stride 9 (3 groups of indices into v/vt/vn)
	int* f;
	size_t f_size;
	size_t f_cap;

	~this()
	{
		free(v);
		free(vt);
		free(vn);
		free(f);
	}
}

void objParseLine(ref ObjFile result, const(char)* line)
{
	if (line[0] == 'v' && line[1] == ' ')
	{
		const(char)* s = line + 2;

		float x = parseFloat(s, &s);
		float y = parseFloat(s, &s);
		float z = parseFloat(s, &s);

		if (result.v_size + 3 > result.v_cap)
			growArray!float(result.v, result.v_cap);

		result.v[result.v_size++] = x;
		result.v[result.v_size++] = y;
		result.v[result.v_size++] = z;
	}
	else if (line[0] == 'v' && line[1] == 't' && line[2] == ' ')
	{
		const(char)* s = line + 3;

		float u = parseFloat(s, &s);
		float v = parseFloat(s, &s);
		float w = parseFloat(s, &s);

		if (result.vt_size + 3 > result.vt_cap)
			growArray!float(result.vt, result.vt_cap);

		result.vt[result.vt_size++] = u;
		result.vt[result.vt_size++] = v;
		result.vt[result.vt_size++] = w;
	}
	else if (line[0] == 'v' && line[1] == 'n' && line[2] == ' ')
	{
		const(char)* s = line + 3;

		float x = parseFloat(s, &s);
		float y = parseFloat(s, &s);
		float z = parseFloat(s, &s);

		if (result.vn_size + 3 > result.vn_cap)
			growArray!float(result.vn, result.vn_cap);

		result.vn[result.vn_size++] = x;
		result.vn[result.vn_size++] = y;
		result.vn[result.vn_size++] = z;
	}
	else if (line[0] == 'f' && line[1] == ' ')
	{
		const(char)* s = line + 2;

		size_t v = result.v_size / 3;
		size_t vt = result.vt_size / 3;
		size_t vn = result.vn_size / 3;

		int fv = 0;
		int[3][3] f;

		while (*s)
		{
			int vi = 0, vti = 0, vni = 0;
			s = parseFace(s, vi, vti, vni);

			if (vi == 0)
				break;

			f[fv][0] = fixupIndex(vi, v);
			f[fv][1] = fixupIndex(vti, vt);
			f[fv][2] = fixupIndex(vni, vn);

			if (fv == 2)
			{
				if (result.f_size + 9 > result.f_cap)
					growArray!int(result.f, result.f_cap);

				memcpy(cast(void*) &result.f[result.f_size], cast(void*) f.ptr, 9 * int.sizeof);
				result.f_size += 9;

				f[1][0] = f[2][0];
				f[1][1] = f[2][1];
				f[1][2] = f[2][2];
			}
			else
			{
				fv++;
			}
		}
	}
}

bool objParseFile(ref ObjFile result, const(char)* path)
{
	auto file = fopen(path, "rb");
	if (!file)
		return false;
	scope(exit) fclose(file);

	char[65536] buffer;
	size_t size = 0;

	while (!feof(file))
	{
		size += fread(buffer.ptr + size, 1, buffer.length - size, file);

		size_t line = 0;

		while (line < size)
		{
			// find the end of current line
			void* eol = memchr(buffer.ptr + line, '\n', size - line);
			if (!eol)
				break;

			// zero-terminate for objParseLine
			size_t next = cast(char*)(eol) - buffer.ptr;

			buffer[next] = 0;

			// process next line
			objParseLine(result, buffer.ptr + line);

			line = next + 1;
		}
		// move prefix of the last line in the buffer to the beginning of the buffer for next iteration
		assert(line <= size);

		memmove(buffer.ptr, buffer.ptr + line, size - line);
		size -= line;
	}

	if (size)
	{
		// process last line
		assert(size < buffer.sizeof);
		buffer[size] = 0;
		objParseLine(result, buffer.ptr);
	}

	return true;
}

bool objValidate(const ref ObjFile result)
{
	size_t v = result.v_size / 3;
	size_t vt = result.vt_size / 3;
	size_t vn = result.vn_size / 3;

	for (size_t i = 0; i < result.f_size; i += 3)
	{
		int vi = result.f[i + 0];
		int vti = result.f[i + 1];
		int vni = result.f[i + 2];

		if (vi < 0)
			return false;

		if (vi >= 0 && cast(size_t)(vi) >= v)
			return false;

		if (vti >= 0 && cast(size_t)(vti) >= vt)
			return false;

		if (vni >= 0 && cast(size_t)(vni) >= vn)
			return false;
	}

	return true;
}