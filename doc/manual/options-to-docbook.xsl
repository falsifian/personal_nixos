<?xml version="1.0"?>

<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:str="http://exslt.org/strings"
                xmlns:xlink="http://www.w3.org/1999/xlink"
                xmlns="http://docbook.org/ns/docbook"
                extension-element-prefixes="str"
                >

  <xsl:output method='xml' encoding="UTF-8" />

  
  <xsl:template match="/expr/list">

      <variablelist>

        <xsl:for-each select="attrs">

          <varlistentry>
             <term>
               <option>
                 <xsl:for-each select="attr[@name = 'name']/string">
                   <xsl:value-of select="@value" />
		   <xsl:if test="position() != last()">.</xsl:if>
                 </xsl:for-each>
               </option>
             </term>

             <listitem>

               <para>
                 <xsl:value-of disable-output-escaping="yes"
                               select="attr[@name = 'description']/string/@value" />
               </para>

               <para>
                 <emphasis>Default:</emphasis>
                 <xsl:text> </xsl:text>
                 <xsl:choose>
                   <xsl:when test="attr[@name = 'default']">
                     <literal>
                       <xsl:apply-templates select="attr[@name = 'default']" />
                     </literal>
                   </xsl:when>
                   <xsl:otherwise>
                     none
                   </xsl:otherwise>
                 </xsl:choose>
               </para>

               <xsl:if test="attr[@name = 'example']">
                 <para>
                   <emphasis>Example:</emphasis>
                   <xsl:text> </xsl:text>
                   <literal>
                     <xsl:apply-templates select="attr[@name = 'example']" />
                   </literal>
                 </para>
               </xsl:if>
               
             </listitem>

          </varlistentry>

        </xsl:for-each>

      </variablelist>

  </xsl:template>


  <xsl:template match="string">
    <!-- !!! escaping -->
    <xsl:text>"</xsl:text><xsl:value-of select="@value" /><xsl:text>"</xsl:text>
  </xsl:template>
  
  
  <xsl:template match="int">
    <xsl:value-of select="@value" />
  </xsl:template>
  
  
  <xsl:template match="bool[@value = 'true']">
    <xsl:text>true</xsl:text>
  </xsl:template>
  
  
  <xsl:template match="bool[@value = 'false']">
    <xsl:text>false</xsl:text>
  </xsl:template>
  
  
  <xsl:template match="list">
    [
    <xsl:for-each select="*">
      <xsl:apply-templates select="." />
      <xsl:text> </xsl:text>
    </xsl:for-each>
    ]
  </xsl:template>
  
  
  <xsl:template match="attrs">
    {
    <xsl:for-each select="attr">
      <xsl:value-of select="@name" />
      <xsl:text> = </xsl:text>
      <xsl:apply-templates select="*" /><xsl:text>; </xsl:text>
    </xsl:for-each>
    }
  </xsl:template>
  
  
  <xsl:template match="derivation">
    <xsl:choose>
      <xsl:when test="attr[@name = 'url']/string/@value">
        <emphasis>(download of <xsl:value-of select="attr[@name = 'url']/string/@value" />)</emphasis>
      </xsl:when>
      <xsl:otherwise>
        <emphasis>(build of <xsl:value-of select="attr[@name = 'name']/string/@value" />)</emphasis>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  
</xsl:stylesheet>
